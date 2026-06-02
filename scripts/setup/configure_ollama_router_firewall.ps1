param(
    [string]$RuleName = "IA-LAB Ollama Router 11436",
    [int]$Port = 11436,
    [string]$RemoteIp = "LocalSubnet",
    [string]$Profile = "domain,private",
    [switch]$Preview
)

$ErrorActionPreference = "Stop"

$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator
)

if ($Preview) {
    Write-Host "Preview: regra=$RuleName porta=$Port remoteip=$RemoteIp profile=$Profile"
    netsh advfirewall firewall show rule name="$RuleName" verbose
    exit 0
}

if (-not $isAdmin) {
    throw "Execute este script em um PowerShell aberto como Administrador."
}

$existing = netsh advfirewall firewall show rule name="$RuleName" 2>$null
if ($LASTEXITCODE -eq 0 -and ($existing -join "`n") -match [regex]::Escape($RuleName)) {
    Write-Host "Atualizando regra existente: $RuleName"
    netsh advfirewall firewall set rule `
        name="$RuleName" `
        new `
        dir=in `
        action=allow `
        protocol=TCP `
        localport=$Port `
        remoteip=$RemoteIp `
        profile=$Profile | Out-Host
}
else {
    netsh advfirewall firewall add rule `
        name="$RuleName" `
        dir=in `
        action=allow `
        protocol=TCP `
        localport=$Port `
        remoteip=$RemoteIp `
        profile=$Profile | Out-Host
}

netsh advfirewall firewall show rule name="$RuleName" verbose
