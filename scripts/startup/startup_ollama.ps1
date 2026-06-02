$ErrorActionPreference = "Stop"

$gpuHostValue = "0.0.0.0:11434"
$cpuHostValue = "0.0.0.0:11435"
$routerPort = 11436
$gpuPort = 11434
$cpuPort = 11435
$proxyUrl = "http://127.0.0.1:18080"
$proxyPort = 18080
$noProxy = "localhost,127.0.0.1,::1,0.0.0.0,10.14.0.226"

Write-Host "Configurando variaveis Ollama..."

[Environment]::SetEnvironmentVariable("OLLAMA_HOST", $gpuHostValue, "User")
[Environment]::SetEnvironmentVariable("HTTP_PROXY", $proxyUrl, "User")
[Environment]::SetEnvironmentVariable("HTTPS_PROXY", $proxyUrl, "User")
[Environment]::SetEnvironmentVariable("ALL_PROXY", $proxyUrl, "User")
[Environment]::SetEnvironmentVariable("NO_PROXY", $noProxy, "User")
[Environment]::SetEnvironmentVariable("no_proxy", $noProxy, "User")

$env:OLLAMA_HOST = $gpuHostValue
$env:HTTP_PROXY = $proxyUrl
$env:HTTPS_PROXY = $proxyUrl
$env:ALL_PROXY = $proxyUrl
$env:NO_PROXY = $noProxy
$env:no_proxy = $noProxy

$pxListening = Test-NetConnection 127.0.0.1 -Port $proxyPort -InformationLevel Quiet
if (-not $pxListening) {
    Write-Warning "PX nao esta escutando em 127.0.0.1:$proxyPort. Downloads do Ollama podem falhar em rede corporativa."
}

$ollama = Get-Command ollama -ErrorAction Stop
$router = Join-Path $PSScriptRoot "ollama_router.ps1"
$scriptsRoot = Split-Path -Parent $PSScriptRoot
$logDir = Join-Path $scriptsRoot "logs"
New-Item -ItemType Directory -Path $logDir -Force | Out-Null

function Start-OllamaBackend {
    param(
        [string]$Name,
        [string]$HostValue,
        [string]$Library,
        [int]$Port
    )

    $alreadyListening = Test-NetConnection 127.0.0.1 -Port $Port -InformationLevel Quiet
    if ($alreadyListening) {
        Write-Host "$Name ja esta escutando na porta $Port."
        return
    }

    $libraryCommand = if ($Library) {
        "`$env:OLLAMA_LLM_LIBRARY='$Library';"
    }
    else {
        "Remove-Item Env:OLLAMA_LLM_LIBRARY -ErrorAction SilentlyContinue;"
    }

    $command = "`$env:OLLAMA_HOST='$HostValue'; $libraryCommand & '$($ollama.Source)' serve"
    Start-Process -WindowStyle Hidden -FilePath "powershell.exe" -ArgumentList @(
        "-NoProfile",
        "-WindowStyle",
        "Hidden",
        "-Command",
        $command
    )
}

function Wait-Port {
    param([string]$Name, [int]$Port)

    Write-Host "Aguardando $Name na porta $Port..."
    for ($i = 1; $i -le 60; $i++) {
        $ready = Test-NetConnection 127.0.0.1 -Port $Port -InformationLevel Quiet
        if ($ready) {
            Write-Host "$Name pronto em 127.0.0.1:$Port"
            return
        }
        Start-Sleep -Seconds 1
    }

    throw "$Name nao abriu a porta $Port"
}

Write-Host "Iniciando Ollama GPU, Ollama CPU e roteador..."

Start-OllamaBackend "Ollama GPU" $gpuHostValue $null $gpuPort
Start-OllamaBackend "Ollama CPU" $cpuHostValue "cpu_avx2" $cpuPort

Wait-Port "Ollama GPU" $gpuPort
Wait-Port "Ollama CPU" $cpuPort

$routerListening = Test-NetConnection 127.0.0.1 -Port $routerPort -InformationLevel Quiet
if (-not $routerListening) {
    $routerOutLog = Join-Path $logDir "ollama_router.out.log"
    $routerErrLog = Join-Path $logDir "ollama_router.err.log"
    $routerCommand = "& '$router' 1> '$routerOutLog' 2> '$routerErrLog'"
    Start-Process -WindowStyle Hidden -FilePath "powershell.exe" -ArgumentList @(
        "-NoProfile",
        "-ExecutionPolicy",
        "Bypass",
        "-Command",
        $routerCommand
    )
}
else {
    Write-Host "Roteador Ollama ja esta escutando na porta $routerPort."
}

Wait-Port "Roteador Ollama" $routerPort
