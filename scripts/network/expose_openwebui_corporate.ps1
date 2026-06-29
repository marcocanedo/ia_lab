param(
    [string]$HostListenAddress = "10.14.0.226",
    [int]$ListenPort = 3000,
    [string]$VmName = "ia-lab",
    [string]$VmAddress,
    [int]$VmPort = 3000,
    [string]$FirewallRuleName = "IA-LAB OpenWebUI Corporate 3000",
    [string]$RemoteIp = "LocalSubnet",
    [switch]$Preview
)

$ErrorActionPreference = "Stop"

$backupRoot = Join-Path (Split-Path $PSScriptRoot -Parent) "logs\network"
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$backupDir = Join-Path $backupRoot "expose_openwebui_$timestamp"

function Assert-Administrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw "Execute este script em PowerShell como Administrador. netsh portproxy e firewall exigem elevacao."
    }
}

function Save-CommandOutput {
    param(
        [string]$FileName,
        [scriptblock]$Command
    )

    $path = Join-Path $backupDir $FileName
    try {
        & $Command 2>&1 | Out-File -FilePath $path -Encoding UTF8
    }
    catch {
        $_.Exception.Message | Out-File -FilePath $path -Encoding UTF8
    }
}

function Test-TcpPort {
    param(
        [string]$Address,
        [int]$Port
    )

    return Test-NetConnection $Address -Port $Port -InformationLevel Quiet
}

function Get-MultipassVmIPv4 {
    param([string]$Name)

    $ipv4Line = multipass info $Name | Select-String "^\s*IPv4:" | Select-Object -First 1
    if (-not $ipv4Line) {
        throw "Nao foi possivel detectar IPv4 da VM $Name."
    }

    $address = (($ipv4Line.ToString() -split ":", 2)[1]).Trim()
    if (-not $address) {
        throw "IPv4 vazio para VM $Name."
    }

    return $address
}

if (-not $VmAddress) {
    $VmAddress = Get-MultipassVmIPv4 -Name $VmName
}

New-Item -ItemType Directory -Force -Path $backupDir | Out-Null

Save-CommandOutput "portproxy_before.txt" { netsh interface portproxy show all }
Save-CommandOutput "firewall_openwebui_before.txt" { netsh advfirewall firewall show rule name=all dir=in | Select-String -Pattern "OpenWebUI|3000|$([regex]::Escape($FirewallRuleName))" -Context 0,10 }
Save-CommandOutput "ipconfig_before.txt" { ipconfig /all }
Save-CommandOutput "netstat_tcp_before.txt" { netstat -ano -p tcp }

$state = [pscustomobject]@{
    generated_at = (Get-Date).ToString("s")
    host_listen_address = $HostListenAddress
    listen_port = $ListenPort
    vm_address = $VmAddress
    vm_port = $VmPort
    firewall_rule_name = $FirewallRuleName
    remote_ip = $RemoteIp
    preserved_local_portproxy = "127.0.0.1:$ListenPort"
    preview = [bool]$Preview
}
$state | ConvertTo-Json -Depth 4 | Set-Content -Path (Join-Path $backupDir "state.json") -Encoding UTF8

Write-Host "Backup salvo em: $backupDir"
Write-Host "Validando Open WebUI na VM em ${VmAddress}:$VmPort..."
if (-not (Test-TcpPort $VmAddress $VmPort)) {
    throw "Open WebUI nao respondeu em ${VmAddress}:$VmPort. Nenhuma exposicao corporativa foi aplicada."
}

if ($Preview) {
    Write-Host ""
    Write-Host "Preview: nenhuma alteracao aplicada."
    Write-Host "  portproxy corporativo: ${HostListenAddress}:$ListenPort -> ${VmAddress}:$VmPort"
    Write-Host "  firewall: $FirewallRuleName TCP $ListenPort RemoteIP=$RemoteIp"
    Write-Host "  portproxy local preservado: 127.0.0.1:$ListenPort"
    exit 0
}

Assert-Administrator

Write-Host "Preservando portproxy local 127.0.0.1:$ListenPort quando existir."
Write-Host "Atualizando portproxy corporativo ${HostListenAddress}:$ListenPort -> ${VmAddress}:$VmPort..."
netsh interface portproxy delete v4tov4 listenaddress=$HostListenAddress listenport=$ListenPort | Out-Null
netsh interface portproxy add v4tov4 listenaddress=$HostListenAddress listenport=$ListenPort connectaddress=$VmAddress connectport=$VmPort

$existingRule = netsh advfirewall firewall show rule name="$FirewallRuleName" 2>&1
if ($existingRule -match "Nenhuma regra corresponde|No rules match") {
    Write-Host "Criando regra de firewall $FirewallRuleName para TCP $ListenPort, RemoteIP=$RemoteIp..."
    netsh advfirewall firewall add rule name="$FirewallRuleName" dir=in action=allow protocol=TCP localip=$HostListenAddress localport=$ListenPort remoteip=$RemoteIp profile=domain,private
}
else {
    Write-Host "Regra de firewall $FirewallRuleName ja existe; mantendo."
}

Save-CommandOutput "portproxy_after.txt" { netsh interface portproxy show all }
Save-CommandOutput "firewall_openwebui_after.txt" { netsh advfirewall firewall show rule name=all dir=in | Select-String -Pattern "OpenWebUI|3000|$([regex]::Escape($FirewallRuleName))" -Context 0,10 }

$localhostOk = Test-TcpPort "localhost" $ListenPort
$loopbackOk = Test-TcpPort "127.0.0.1" $ListenPort
$corporateOk = Test-TcpPort $HostListenAddress $ListenPort

$validation = [pscustomobject]@{
    generated_at = (Get-Date).ToString("s")
    localhost_3000 = $localhostOk
    loopback_3000 = $loopbackOk
    corporate_3000 = $corporateOk
    vm_3000 = Test-TcpPort $VmAddress $VmPort
    ollama_not_modified = "11434 untouched"
    ssh_not_modified = "22 untouched"
}
$validation | ConvertTo-Json -Depth 4 | Set-Content -Path (Join-Path $backupDir "validation.json") -Encoding UTF8

Write-Host ""
Write-Host "Validacao:"
Write-Host "  localhost:$ListenPort      $localhostOk"
Write-Host "  127.0.0.1:$ListenPort      $loopbackOk"
Write-Host "  ${HostListenAddress}:$ListenPort $corporateOk"
Write-Host "  ${VmAddress}:$VmPort       $($validation.vm_3000)"
Write-Host ""

if (-not ($localhostOk -and $loopbackOk -and $corporateOk)) {
    throw "Exposicao aplicada, mas a validacao local nao passou integralmente. Consulte $backupDir."
}

Write-Host "Open WebUI exposto em http://${HostListenAddress}:$ListenPort"
