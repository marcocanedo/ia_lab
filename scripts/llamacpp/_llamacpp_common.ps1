$ErrorActionPreference = "Stop"

$script:LabRoot = "C:\IA-LAB"
$script:LlamaRoot = Join-Path $script:LabRoot "llama.cpp"
$script:ModelRoot = Join-Path $script:LabRoot "models\gguf"
$script:LogRoot = Join-Path $script:LabRoot "scripts\logs\llamacpp"
$script:PidRoot = Join-Path $script:LogRoot "pids"

function Initialize-LlamaCppPaths {
    foreach ($path in @($script:LlamaRoot, $script:ModelRoot, $script:LogRoot, $script:PidRoot)) {
        New-Item -ItemType Directory -Path $path -Force | Out-Null
    }
}

function Get-LlamaServerPath {
    Initialize-LlamaCppPaths

    $currentFile = Join-Path $script:LlamaRoot "current_server.txt"
    if (Test-Path $currentFile) {
        $candidate = (Get-Content -LiteralPath $currentFile -Raw).Trim()
        if ($candidate -and (Test-Path $candidate)) {
            return $candidate
        }
    }

    $server = Get-ChildItem -LiteralPath $script:LlamaRoot -Filter "llama-server.exe" -Recurse -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1
    if (-not $server) {
        throw "llama-server.exe nao encontrado. Execute C:\IA-LAB\scripts\llamacpp\install_llamacpp.ps1 primeiro."
    }

    $server.FullName | Set-Content -Encoding ASCII -LiteralPath $currentFile
    return $server.FullName
}

function Get-GgufFiles {
    param(
        [Parameter(Mandatory = $true)][string]$ModelDirectory,
        [Parameter(Mandatory = $true)][string]$Pattern
    )

    $dir = Join-Path $script:ModelRoot $ModelDirectory
    if (-not (Test-Path $dir)) {
        throw "Diretorio de modelo nao encontrado: $dir"
    }

    $files = @(Get-ChildItem -LiteralPath $dir -Filter $Pattern -File | Sort-Object Name)
    if ($files.Count -eq 0) {
        throw "Nenhum GGUF encontrado em $dir com padrao $Pattern. Execute download_models.ps1."
    }

    return $files
}

function Test-LocalPortFree {
    param([Parameter(Mandatory = $true)][int]$Port)

    $listening = Test-NetConnection 127.0.0.1 -Port $Port -InformationLevel Quiet
    if ($listening) {
        throw "Porta $Port ja esta em uso em 127.0.0.1. Pare o processo atual ou escolha outro endpoint."
    }
}

function Start-LlamaModel {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][string]$ModelDirectory,
        [Parameter(Mandatory = $true)][string]$ModelPattern,
        [Parameter(Mandatory = $true)][int]$Port,
        [Parameter(Mandatory = $true)][int]$Context,
        [int]$GpuLayers = 999,
        [string]$ModelAlias
    )

    Initialize-LlamaCppPaths
    Test-LocalPortFree -Port $Port

    $server = Get-LlamaServerPath
    $modelFiles = @(Get-GgufFiles -ModelDirectory $ModelDirectory -Pattern $ModelPattern)
    $modelArg = $modelFiles[0].FullName
    $alias = if ($ModelAlias) { $ModelAlias } else { $Name }
    $safeName = ($Name -replace "[^A-Za-z0-9_.-]", "_").ToLowerInvariant()
    $outLog = Join-Path $script:LogRoot "$safeName.log"
    $errLog = Join-Path $script:LogRoot "$safeName.err.log"
    $pidFile = Join-Path $script:PidRoot "$safeName.pid"

    $args = @(
        "-m", $modelArg,
        "--host", "127.0.0.1",
        "--port", "$Port",
        "-ngl", "$GpuLayers",
        "-c", "$Context",
        "--alias", $alias
    )

    Write-Host "Iniciando $Name em http://127.0.0.1:$Port/v1"
    Write-Host "Modelo: $modelArg"
    Write-Host "Log: $outLog"

    $process = Start-Process -FilePath $server -ArgumentList $args -WindowStyle Hidden -RedirectStandardOutput $outLog -RedirectStandardError $errLog -PassThru
    $process.Id | Set-Content -Encoding ASCII -LiteralPath $pidFile

    for ($i = 1; $i -le 90; $i++) {
        Start-Sleep -Seconds 1
        if ($process.HasExited) {
            throw "$Name encerrou durante a inicializacao. Veja $errLog"
        }
        if (Test-NetConnection 127.0.0.1 -Port $Port -InformationLevel Quiet) {
            Write-Host "$Name pronto em 127.0.0.1:$Port"
            return
        }
    }

    throw "$Name nao abriu a porta $Port em 90 segundos. Veja $errLog"
}

function Invoke-LlamaChatTest {
    param(
        [Parameter(Mandatory = $true)][int]$Port,
        [Parameter(Mandatory = $true)][string]$Model
    )

    $body = @{
        model = $Model
        messages = @(@{ role = "user"; content = "Responda apenas: ok" })
        max_tokens = 16
        temperature = 0
    } | ConvertTo-Json -Depth 6

    return Invoke-RestMethod -Method Post -Uri "http://127.0.0.1:$Port/v1/chat/completions" -ContentType "application/json" -Body $body -TimeoutSec 120
}
