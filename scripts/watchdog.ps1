$ErrorActionPreference = "Continue"

$scriptRoot = "C:\IA-LAB\scripts"
$logDir = Join-Path $scriptRoot "logs"
$logFile = Join-Path $logDir ("watchdog_{0:yyyyMMdd}.log" -f (Get-Date))

New-Item -ItemType Directory -Force -Path $logDir | Out-Null

function Write-Log {
    param([string]$Message)
    $line = "{0} {1}" -f (Get-Date -Format s), $Message
    Add-Content -Encoding UTF8 -Path $logFile -Value $line
    Write-Output $line
}

function Test-PortQuiet {
    param([int]$Port)
    return Test-NetConnection 127.0.0.1 -Port $Port -InformationLevel Quiet
}

Write-Log "Watchdog iniciado"

if (-not (Test-PortQuiet 18080)) {
    Write-Log "PX indisponivel; executando startup_px.ps1"
    & (Join-Path $scriptRoot "startup_px.ps1")
}

if (-not (Test-PortQuiet 11434)) {
    Write-Log "Ollama indisponivel; executando startup_ollama.ps1"
    & (Join-Path $scriptRoot "startup_ollama.ps1")
}

try {
    Invoke-RestMethod -Uri "http://127.0.0.1:3000/api/config" -TimeoutSec 10 | Out-Null
    Write-Log "Open WebUI OK"
}
catch {
    Write-Log "Open WebUI falhou: $($_.Exception.Message)"
    Write-Log "Reiniciando container open-webui na VM ia-lab"
    multipass exec ia-lab -- docker restart open-webui | Out-Null
    Start-Sleep -Seconds 15
}

if (-not (Test-PortQuiet 3000)) {
    Write-Log "Portproxy/Open WebUI indisponivel; executando startup_vm.ps1"
    & (Join-Path $scriptRoot "startup_vm.ps1")
}

Write-Log "Watchdog concluido"
