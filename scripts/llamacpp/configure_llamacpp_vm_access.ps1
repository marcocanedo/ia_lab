param(
    [string]$VmName = "ia-lab",
    [string]$HostListenAddress,
    [string]$RemoteIp = "LocalSubnet",
    [string]$FirewallRuleName = "IA-LAB llama.cpp VM Access 8001-8003",
    [switch]$Preview
)

$ErrorActionPreference = "Stop"
$backupRoot = "D:\IA-LAB\scripts\logs\llamacpp\network"
$backupDir = Join-Path $backupRoot ("configure_vm_access_{0:yyyyMMdd_HHmmss}" -f (Get-Date))
New-Item -ItemType Directory -Path $backupDir -Force | Out-Null

function Assert-Administrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw "Execute em PowerShell como Administrador. netsh portproxy e firewall exigem elevacao."
    }
}

function Save-Output {
    param([string]$Name, [scriptblock]$Command)
    & $Command 2>&1 | Out-File -Encoding UTF8 -FilePath (Join-Path $backupDir $Name)
}

function Get-MultipassGateway {
    param([string]$Name)

    $gateway = multipass exec $Name -- sh -lc "ip route show default | awk '{print `$3; exit}'"
    $gateway = ($gateway | Select-Object -First 1).Trim()
    if (-not $gateway) {
        throw "Nao foi possivel detectar gateway da VM $Name."
    }

    return $gateway
}

if (-not $HostListenAddress) {
    $HostListenAddress = Get-MultipassGateway -Name $VmName
}

Save-Output "portproxy_before.txt" { netsh interface portproxy show all }
Save-Output "firewall_before.txt" { netsh advfirewall firewall show rule name=all dir=in | Select-String -Pattern "llama|8001|8002|8003|$([regex]::Escape($FirewallRuleName))" -Context 0,8 }
Save-Output "ipconfig_before.txt" { ipconfig /all }

if ($Preview) {
    Write-Host "Preview: nenhuma alteracao aplicada."
    Write-Host "  portproxy: ${HostListenAddress}:8001-8003 -> 127.0.0.1:8001-8003"
    Write-Host "  firewall: $FirewallRuleName TCP 8001-8003 RemoteIP=$RemoteIp"
    Write-Host "Backup: $backupDir"
    exit 0
}

Assert-Administrator

foreach ($port in 8001,8002,8003) {
    Write-Host "Configurando portproxy ${HostListenAddress}:$port -> 127.0.0.1:$port"
    netsh interface portproxy delete v4tov4 listenaddress=$HostListenAddress listenport=$port | Out-Null
    netsh interface portproxy add v4tov4 listenaddress=$HostListenAddress listenport=$port connectaddress=127.0.0.1 connectport=$port | Out-Null
}

$existingRule = netsh advfirewall firewall show rule name="$FirewallRuleName" 2>&1
if ($existingRule -match "Nenhuma regra corresponde|No rules match") {
    netsh advfirewall firewall add rule name="$FirewallRuleName" dir=in action=allow protocol=TCP localip=$HostListenAddress localport=8001-8003 remoteip=$RemoteIp profile=domain,private | Out-Null
}
else {
    Write-Host "Regra de firewall ja existe: $FirewallRuleName"
}

Save-Output "portproxy_after.txt" { netsh interface portproxy show all }
Save-Output "firewall_after.txt" { netsh advfirewall firewall show rule name="$FirewallRuleName" verbose }

Write-Host "Acesso VM configurado. Backup: $backupDir"
Write-Host "Endpoints para o Open WebUI: http://${HostListenAddress}:8001/v1 ; http://${HostListenAddress}:8002/v1 ; http://${HostListenAddress}:8003/v1"
