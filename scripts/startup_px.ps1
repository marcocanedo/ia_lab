$ErrorActionPreference = "Stop"

$pxPath = "C:\IA-LAB\px\px.exe"
$port = 18080

Write-Host "Iniciando PX..."

if (-not (Test-Path $pxPath)) {
    throw "PX nao encontrado em $pxPath"
}

$pxRunning = Get-Process px -ErrorAction SilentlyContinue | Where-Object {
    $_.Path -eq $pxPath
}

if (-not $pxRunning) {
    Start-Process -WindowStyle Hidden $pxPath -ArgumentList "--listen=0.0.0.0 --port=$port"
}
else {
    Write-Host "PX ja esta em execucao."
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
