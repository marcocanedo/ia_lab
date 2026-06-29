param(
    [switch]$Force
)

$ErrorActionPreference = "Stop"
. "$PSScriptRoot\_llamacpp_common.ps1"
Initialize-LlamaCppPaths

$releaseApi = "https://api.github.com/repos/ggml-org/llama.cpp/releases/latest"
$downloadRoot = Join-Path $script:LlamaRoot "downloads"
$releaseRoot = Join-Path $script:LlamaRoot "releases"
New-Item -ItemType Directory -Path $downloadRoot, $releaseRoot -Force | Out-Null

$proxyUrl = "http://127.0.0.1:18080"
$useProxy = Test-NetConnection 127.0.0.1 -Port 18080 -InformationLevel Quiet
if ($useProxy) {
    $env:HTTP_PROXY = $proxyUrl
    $env:HTTPS_PROXY = $proxyUrl
    $env:ALL_PROXY = $proxyUrl
    $env:NO_PROXY = "localhost,127.0.0.1,::1,0.0.0.0,10.14.0.226,172.25.112.1"
    $env:no_proxy = $env:NO_PROXY
    Write-Host "Usando PX local para downloads: $proxyUrl"
}

Write-Host "Consultando releases oficiais do llama.cpp..."
$webArgs = @{ Headers = @{ "User-Agent" = "IA-LAB-llamacpp-installer" }; TimeoutSec = 60 }
if ($useProxy) { $webArgs.Proxy = $proxyUrl }

$latestRelease = Invoke-RestMethod -Uri $releaseApi @webArgs
$releases = @(Invoke-RestMethod -Uri "https://api.github.com/repos/ggml-org/llama.cpp/releases?per_page=20" @webArgs)

$release = $null
$cudaAsset = $null
foreach ($candidateRelease in @($latestRelease) + $releases) {
    $candidateAsset = @($candidateRelease.assets |
        Where-Object { $_.name -match '(?i)win' -and $_.name -match '(?i)x64' -and $_.name -match '(?i)cuda' -and $_.name -match '\.zip$' -and $_.name -notmatch '(?i)cudart' } |
        Sort-Object name |
        Select-Object -First 1)

    if ($candidateAsset.Count -gt 0) {
        $release = $candidateRelease
        $cudaAsset = $candidateAsset[0]
        break
    }
}

if (-not $release -or -not $cudaAsset) {
    throw "Nenhum artefato oficial Windows x64 CUDA encontrado nos releases recentes. Build local nao sera feito automaticamente."
}

$tag = $release.tag_name
$targetDir = Join-Path $releaseRoot $tag

if ((Test-Path (Join-Path $targetDir "llama-server.exe")) -and -not $Force) {
    $server = Join-Path $targetDir "llama-server.exe"
    $server | Set-Content -Encoding ASCII -LiteralPath (Join-Path $script:LlamaRoot "current_server.txt")
    Write-Host "llama.cpp $tag ja instalado: $server"
    exit 0
}

$assets = @($release.assets)
$cudaVersion = if ($cudaAsset.name -match 'cuda-([0-9.]+)-x64') { $Matches[1] } else { "" }
$runtimeAssets = @($assets |
    Where-Object {
        $_.name -match '(?i)win' -and
        $_.name -match '(?i)x64' -and
        $_.name -match '(?i)cudart|cuda-runtime' -and
        $_.name -match '\.zip$' -and
        ($cudaVersion -eq "" -or $_.name -match [regex]::Escape($cudaVersion))
    })

New-Item -ItemType Directory -Path $targetDir -Force | Out-Null

function Save-Asset {
    param($Asset)
    $zipPath = Join-Path $downloadRoot $Asset.name
    if ((-not (Test-Path $zipPath)) -or $Force) {
        Write-Host "Baixando $($Asset.name)..."
        $downloadArgs = @{
            Uri = $Asset.browser_download_url
            OutFile = $zipPath
            Headers = @{ "User-Agent" = "IA-LAB-llamacpp-installer" }
            TimeoutSec = 1800
        }
        if ($useProxy) { $downloadArgs.Proxy = $proxyUrl }
        Invoke-WebRequest @downloadArgs
    }
    else {
        Write-Host "Arquivo ja existe: $zipPath"
    }

    Write-Host "Extraindo $($Asset.name)..."
    Expand-Archive -LiteralPath $zipPath -DestinationPath $targetDir -Force
    return $zipPath
}

$downloaded = @()
$downloaded += Save-Asset -Asset $cudaAsset
foreach ($asset in $runtimeAssets) {
    $downloaded += Save-Asset -Asset $asset
}

$server = Get-ChildItem -LiteralPath $targetDir -Filter "llama-server.exe" -Recurse |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1
if (-not $server) {
    throw "O release foi extraido, mas llama-server.exe nao foi encontrado em $targetDir."
}

$server.FullName | Set-Content -Encoding ASCII -LiteralPath (Join-Path $script:LlamaRoot "current_server.txt")

$report = Join-Path $script:LabRoot "docs\llamacpp\relatorio_instalacao.md"
New-Item -ItemType Directory -Path (Split-Path $report -Parent) -Force | Out-Null
$lines = @()
$lines += "# Relatorio de instalacao llama.cpp"
$lines += ""
$lines += "- Atualizado em: $(Get-Date -Format s)"
$lines += "- Release mais recente consultado: $($latestRelease.tag_name)"
$lines += "- Release: $tag"
$lines += "- URL: $($release.html_url)"
$lines += "- Executavel: $($server.FullName)"
$lines += "- Artefato principal: $($cudaAsset.name)"
$lines += "- Runtime CUDA/CUDART: $(if ($runtimeAssets.Count -gt 0) { ($runtimeAssets.name -join ', ') } else { 'nao identificado no release' })"
$lines += ""
$lines += "## Arquivos baixados"
foreach ($file in $downloaded) {
    $hash = Get-FileHash -Algorithm SHA256 -LiteralPath $file
    $lines += "- $($hash.Path) - SHA256 $($hash.Hash)"
}
$lines += ""
$lines += "## Pendencias"
$lines += "- Baixar modelos GGUF com `download_models.ps1`."
$lines += "- Executar healthcheck llama.cpp apos iniciar os modelos."
$lines | Set-Content -Encoding UTF8 -LiteralPath $report

Write-Host "llama.cpp instalado: $($server.FullName)"
