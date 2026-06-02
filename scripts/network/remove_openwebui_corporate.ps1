param(
    [string]$HostListenAddress = "10.14.0.226",
    [int]$ListenPort = 3000,
    [string]$FirewallRuleName = "IA-LAB OpenWebUI Corporate 3000",
    [switch]$Preview
)

$ErrorActionPreference = "Stop"

$backupRoot = Join-Path (Split-Path $PSScriptRoot -Parent) "logs\network"
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$backupDir = Join-Path $backupRoot "remove_openwebui_$timestamp"

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

New-Item -ItemType Directory -Force -Path $backupDir | Out-Null

Save-CommandOutput "portproxy_before.txt" { netsh interface portproxy show all }
Save-CommandOutput "firewall_openwebui_before.txt" { netsh advfirewall firewall show rule name=all dir=in | Select-String -Pattern "OpenWebUI|3000|$([regex]::Escape($FirewallRuleName))" -Context 0,10 }

if ($Preview) {
    Write-Host "Preview: nenhuma alteracao aplicada."
    Write-Host "  remover portproxy corporativo: ${HostListenAddress}:$ListenPort"
    Write-Host "  remover firewall: $FirewallRuleName"
    Write-Host "  backup de estado: $backupDir"
    exit 0
}

Assert-Administrator

Write-Host "Removendo somente o portproxy corporativo ${HostListenAddress}:$ListenPort..."
netsh interface portproxy delete v4tov4 listenaddress=$HostListenAddress listenport=$ListenPort | Out-Null

$existingRule = netsh advfirewall firewall show rule name="$FirewallRuleName" 2>&1
if ($existingRule -notmatch "Nenhuma regra corresponde|No rules match") {
    Write-Host "Removendo regra de firewall $FirewallRuleName..."
    netsh advfirewall firewall delete rule name="$FirewallRuleName" | Out-Null
}
else {
    Write-Host "Regra de firewall $FirewallRuleName nao encontrada; nada a remover."
}

Save-CommandOutput "portproxy_after.txt" { netsh interface portproxy show all }
Save-CommandOutput "firewall_openwebui_after.txt" { netsh advfirewall firewall show rule name=all dir=in | Select-String -Pattern "OpenWebUI|3000|$([regex]::Escape($FirewallRuleName))" -Context 0,10 }

$loopbackOk = Test-NetConnection "127.0.0.1" -Port $ListenPort -InformationLevel Quiet
$corporateOk = Test-NetConnection $HostListenAddress -Port $ListenPort -InformationLevel Quiet

$validation = [pscustomobject]@{
    generated_at = (Get-Date).ToString("s")
    loopback_3000_preserved = $loopbackOk
    corporate_3000_removed = (-not $corporateOk)
    ollama_not_modified = "11434 untouched"
    ssh_not_modified = "22 untouched"
}
$validation | ConvertTo-Json -Depth 4 | Set-Content -Path (Join-Path $backupDir "validation.json") -Encoding UTF8

Write-Host ""
Write-Host "Validacao rollback:"
Write-Host "  127.0.0.1:$ListenPort preservado: $loopbackOk"
Write-Host "  ${HostListenAddress}:$ListenPort removido: $(-not $corporateOk)"
Write-Host "Backup salvo em: $backupDir"
