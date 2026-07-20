param(
    [switch]$ConfigureAptProxy
)

$ErrorActionPreference = "Stop"

$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = New-Object Security.Principal.WindowsPrincipal($identity)
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw "Execute este script em PowerShell como Administrador."
}

$multipassExe = "C:\Program Files\Multipass\bin\multipass.exe"
$vboxInstallPath = [Environment]::GetEnvironmentVariable("VBOX_MSI_INSTALL_PATH", "Machine")
if (-not $vboxInstallPath) {
    throw "VBOX_MSI_INSTALL_PATH nao esta configurada no ambiente da maquina."
}

$vboxManage = Join-Path $vboxInstallPath "VBoxManage.exe"
if (-not (Test-Path -LiteralPath $vboxManage -PathType Leaf)) {
    throw "VBoxManage nao encontrado: $vboxManage"
}

Write-Host "Reiniciando Multipass para carregar VBOX_MSI_INSTALL_PATH=$vboxInstallPath"
Restart-Service -Name Multipass -Force
(Get-Service -Name Multipass).WaitForStatus(
    [System.ServiceProcess.ServiceControllerStatus]::Running,
    [TimeSpan]::FromSeconds(60)
)
Start-Sleep -Seconds 5

$driver = (& $multipassExe get local.driver | Out-String).Trim()
if ($driver -ne "virtualbox") {
    throw "Driver Multipass inesperado apos reinicio: $driver"
}

$rebuildScript = Join-Path $PSScriptRoot "rebuild_multipass_vm.ps1"
$rebuildParams = @{}
if ($ConfigureAptProxy) {
    $rebuildParams.ConfigureAptProxy = $true
}

& $rebuildScript @rebuildParams
