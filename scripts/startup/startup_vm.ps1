$ErrorActionPreference = "Stop"

$vmName = "ia-lab"
$listenPort = 3000
$connectPort = 3000

Write-Host "Iniciando VM $vmName..."

multipass start $vmName

Write-Host "Aguardando VM ficar Running..."
for ($i = 1; $i -le 60; $i++) {
    $stateLine = multipass list | Select-String "^\s*$vmName\s+"
    if ($stateLine -and $stateLine.ToString() -match "\sRunning\s") {
        break
    }
    Start-Sleep -Seconds 2
}

Write-Host "Obtendo IP da VM..."

$vmIp = $null
for ($i = 1; $i -le 30; $i++) {
    $ipv4Line = multipass info $vmName | Select-String "^\s*IPv4:" | Select-Object -First 1
    if ($ipv4Line) {
        $vmIp = (($ipv4Line.ToString() -split ":", 2)[1]).Trim()
    }

    if ($vmIp) {
        break
    }

    Start-Sleep -Seconds 2
}

if (-not $vmIp) {
    throw "Nao foi possivel detectar o IP da VM $vmName"
}

Write-Host "IP detectado: $vmIp"

$sshUpdateScript = Join-Path $PSScriptRoot "update_ssh_config.ps1"
if (Test-Path $sshUpdateScript) {
    Write-Host "Atualizando SSH config para VSCode Remote..."
    & $sshUpdateScript
}

Write-Host "Atualizando portproxy..."

netsh interface portproxy delete v4tov4 listenaddress=127.0.0.1 listenport=$listenPort | Out-Null

netsh interface portproxy add v4tov4 `
    listenaddress=127.0.0.1 `
    listenport=$listenPort `
    connectaddress=$vmIp `
    connectport=$connectPort

$proxy = netsh interface portproxy show v4tov4
$expectedProxy = $proxy | Select-String "127\.0\.0\.1\s+$listenPort\s+$([regex]::Escape($vmIp))\s+$connectPort"
if (-not $expectedProxy) {
    throw "Portproxy 127.0.0.1:$listenPort -> ${vmIp}:$connectPort nao foi configurado"
}

Write-Host "Aguardando Open WebUI em 127.0.0.1:$listenPort..."
for ($i = 1; $i -le 60; $i++) {
    $ready = Test-NetConnection 127.0.0.1 -Port $listenPort -InformationLevel Quiet
    if ($ready) {
        Write-Host "Open WebUI acessivel em http://127.0.0.1:$listenPort"
        return
    }
    Start-Sleep -Seconds 2
}

throw "Open WebUI nao respondeu na porta $listenPort"
