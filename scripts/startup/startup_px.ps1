$ErrorActionPreference = "Stop"

$labRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$pxPath = Join-Path $labRoot "px\px.exe"
$port = 18080

Write-Host "Iniciando PX..."

if (-not (Test-Path $pxPath)) {
    throw "PX nao encontrado em $pxPath"
}

$pxRunning = Get-Process px -ErrorAction SilentlyContinue | Where-Object {
    try { $_.Path -eq $pxPath } catch { $false }
}

if ($pxRunning) {
    $listenAll = Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction SilentlyContinue |
        Where-Object { $_.LocalAddress -eq "0.0.0.0" }
    if (-not $listenAll) {
        Write-Host "PX em execucao mas nao escuta em 0.0.0.0. Reiniciando..."
        Stop-Process -Id $pxRunning.Id -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 2
        $pxRunning = $null
    }
    else {
        Write-Host "PX ja esta em execucao em 0.0.0.0:$port."
    }
}

if (-not $pxRunning) {
    Start-Process -WindowStyle Hidden $pxPath -ArgumentList "--listen=0.0.0.0 --port=$port"
}

Write-Host "Aguardando PX na porta $port..."
for ($i = 1; $i -le 30; $i++) {
    $ready = Test-NetConnection 127.0.0.1 -Port $port -InformationLevel Quiet
    if ($ready) {
        Write-Host "PX pronto em 127.0.0.1:$port"
        return
    }
    Start-Sleep -Seconds 1
}

throw "PX nao abriu a porta $port"
