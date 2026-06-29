param(
    [switch]$Force
)

$ErrorActionPreference = "Stop"
. "$PSScriptRoot\_llamacpp_common.ps1"
Initialize-LlamaCppPaths

$proxyUrl = "http://127.0.0.1:18080"
$useProxy = Test-NetConnection 127.0.0.1 -Port 18080 -InformationLevel Quiet
if ($useProxy) {
    $env:HTTP_PROXY = $proxyUrl
    $env:HTTPS_PROXY = $proxyUrl
    $env:ALL_PROXY = $proxyUrl
    $env:NO_PROXY = "localhost,127.0.0.1,::1,0.0.0.0,10.14.0.226,172.25.112.1"
    $env:no_proxy = $env:NO_PROXY
    Write-Host "Usando PX local para Hugging Face: $proxyUrl"
}

$models = @(
    [pscustomobject]@{
        Repo = "Qwen/Qwen2.5-7B-Instruct-GGUF"
        Pattern = "qwen2.5-7b-instruct-q5_k_m*.gguf"
        Directory = "qwen2.5-7b-instruct-q5_k_m"
    },
    [pscustomobject]@{
        Repo = "Qwen/Qwen2.5-Coder-7B-Instruct-GGUF"
        Pattern = "qwen2.5-coder-7b-instruct-q5_k_m-*.gguf"
        Directory = "qwen2.5-coder-7b-instruct-q5_k_m"
    },
    [pscustomobject]@{
        Repo = "Qwen/Qwen2.5-14B-Instruct-GGUF"
        Pattern = "qwen2.5-14b-instruct-q4_k_m*.gguf"
        Directory = "qwen2.5-14b-instruct-q4_k_m"
    }
)

$hf = Get-Command "huggingface-cli" -ErrorAction SilentlyContinue
$pythonLauncher = $null
$pythonPrefix = @()
if (-not $hf) {
    $py = Get-Command "python" -ErrorAction SilentlyContinue
    if ($py -and $py.Source -notmatch "WindowsApps") {
        $pythonLauncher = $py.Source
    }
    else {
        $pyLauncher = Get-Command "py" -ErrorAction SilentlyContinue
        if ($pyLauncher) {
            $pyList = & $pyLauncher.Source -0p 2>$null
            foreach ($line in $pyList) {
                if ($line -match '^\s*-V:[^\s]+\s+\*?\s*(?<path>[A-Z]:\\.*python\.exe)\s*$') {
                    $candidate = $Matches.path
                    if ((Test-Path $candidate) -and $candidate -notmatch "NVIDIA Corporation") {
                        $pythonLauncher = $candidate
                        break
                    }
                }
            }
        }
    }

    if (-not $pythonLauncher) {
        throw "huggingface-cli nao encontrado e Python real nao disponivel. Instale huggingface_hub ou Python antes de baixar os modelos."
    }

    Write-Host "Instalando/validando huggingface_hub no usuario atual..."
    & $pythonLauncher @pythonPrefix -m pip install --user --upgrade huggingface_hub
    if ($LASTEXITCODE -ne 0) {
        throw "Falha ao instalar huggingface_hub."
    }
}

function Invoke-HfDownload {
    param(
        [string]$Repo,
        [string]$Pattern,
        [string]$LocalDir
    )

    if ($hf) {
        & $hf.Source download $Repo --include $Pattern --local-dir $LocalDir --local-dir-use-symlinks False
        return $LASTEXITCODE
    }

    $code = @"
import sys
from huggingface_hub import snapshot_download
snapshot_download(
    repo_id=sys.argv[1],
    local_dir=sys.argv[2],
    allow_patterns=[sys.argv[3]],
    local_dir_use_symlinks=False,
)
"@
    & $pythonLauncher @pythonPrefix -c $code $Repo $LocalDir $Pattern
    return $LASTEXITCODE
}

foreach ($model in $models) {
    $localDir = Join-Path $script:ModelRoot $model.Directory
    New-Item -ItemType Directory -Path $localDir -Force | Out-Null

    $apiUrl = "https://huggingface.co/api/models/$($model.Repo)"
    Write-Host "Validando arquivos em $($model.Repo)..."
    $regex = "^" + (($model.Pattern -replace "\.", "\.") -replace "\*", ".*") + "$"
    $apiArgs = @{ Uri = $apiUrl; Headers = @{ "User-Agent" = "IA-LAB-model-downloader" }; TimeoutSec = 120 }
    if ($useProxy) { $apiArgs.Proxy = $proxyUrl }
    $metadata = Invoke-RestMethod @apiArgs
    $matches = @($metadata.siblings | Where-Object { $_.rfilename -match $regex } | Sort-Object rfilename)
    if ($matches.Count -eq 0) {
        throw "Repo oficial $($model.Repo) nao contem arquivos com padrao $($model.Pattern). Nao usando mirror sem autorizacao."
    }

    $existing = @(Get-ChildItem -LiteralPath $localDir -Filter $model.Pattern -File -ErrorAction SilentlyContinue)
    if ($existing.Count -eq $matches.Count -and -not $Force) {
        Write-Host "Modelo ja parece baixado em $localDir ($($existing.Count) arquivo(s))."
        continue
    }

    Write-Host "Baixando $($model.Repo) para $localDir..."
    $exitCode = Invoke-HfDownload -Repo $model.Repo -Pattern $model.Pattern -LocalDir $localDir
    if ($exitCode -ne 0) {
        throw "Falha no download de $($model.Repo)."
    }
}

$report = Join-Path $script:LabRoot "docs\llamacpp\modelos.md"
$lines = @()
$lines += "# Modelos llama.cpp"
$lines += ""
$lines += "Atualizado em: $(Get-Date -Format s)"
$lines += ""
$lines += "| Modelo | Quantizacao | Porta | Contexto | Arquivos |"
$lines += "| --- | --- | ---: | ---: | --- |"
$rows = @(
    @("Qwen2.5 7B Instruct", "Q5_K_M", 8001, 8192, "qwen2.5-7b-instruct-q5_k_m"),
    @("Qwen2.5 Coder 7B Instruct", "Q5_K_M", 8002, 8192, "qwen2.5-coder-7b-instruct-q5_k_m"),
    @("Qwen2.5 14B Instruct", "Q4_K_M", 8003, 4096, "qwen2.5-14b-instruct-q4_k_m")
)
foreach ($row in $rows) {
    $dir = Join-Path $script:ModelRoot $row[4]
    $files = @(Get-ChildItem -LiteralPath $dir -Filter "*.gguf" -File -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Name)
    $lines += "| $($row[0]) | $($row[1]) | $($row[2]) | $($row[3]) | $($files -join '<br>') |"
}
$lines | Set-Content -Encoding UTF8 -LiteralPath $report

Write-Host "Download/validacao concluido."
