param(
    [string]$InstallLocation = "D:\Program Files\Oracle\VirtualBox",
    [switch]$ConfigureAptProxy
)

$ErrorActionPreference = "Stop"

function Test-IsAdmin {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

if (-not (Test-IsAdmin)) {
    throw "Execute este script em PowerShell como Administrador."
}

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$multipassExe = "C:\Program Files\Multipass\bin\multipass.exe"
$rebuildScript = Join-Path $PSScriptRoot "rebuild_multipass_vm.ps1"

if (-not (Test-Path -LiteralPath $multipassExe -PathType Leaf)) {
    throw "Multipass nao encontrado: $multipassExe"
}

Write-Host "Instalando Oracle VirtualBox em $InstallLocation..."
$cachedInstaller = Get-ChildItem -Path (Join-Path $env:TEMP "WinGet\Oracle.VirtualBox.*\VirtualBox-*-Win.exe") -File -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1

if (-not $cachedInstaller) {
    throw "Instalador validado do VirtualBox nao encontrado no cache do winget."
}

$extractPath = Join-Path $repoRoot "tmp\virtualbox-msi"
$msiLogPath = Join-Path $repoRoot "tmp\virtualbox-install.log"
New-Item -ItemType Directory -Path $extractPath -Force | Out-Null

$extractProcess = Start-Process -FilePath $cachedInstaller.FullName -ArgumentList @("--extract", "--path", $extractPath) -Wait -PassThru
if ($extractProcess.ExitCode -ne 0) {
    throw "A extracao do MSI do VirtualBox falhou com codigo $($extractProcess.ExitCode)."
}

$virtualBoxMsi = Get-ChildItem -LiteralPath $extractPath -Filter "*.msi" -File -Recurse |
    Where-Object { $_.Name -notmatch 'x86' } |
    Select-Object -First 1
if (-not $virtualBoxMsi) {
    throw "MSI x64 do VirtualBox nao encontrado em $extractPath."
}

$msiArguments = '/i "{0}" /qn /norestart INSTALLDIR="{1}" REBOOT=ReallySuppress VBOX_START=0 /L*v "{2}"' -f
    $virtualBoxMsi.FullName, $InstallLocation, $msiLogPath
$installerProcess = Start-Process -FilePath "msiexec.exe" -ArgumentList $msiArguments -Wait -PassThru
if ($installerProcess.ExitCode -notin @(0, 3010)) {
    throw "A instalacao MSI do VirtualBox falhou com codigo $($installerProcess.ExitCode). Log: $msiLogPath"
}

$virtualBoxRegistry = Get-ItemProperty -LiteralPath "HKLM:\SOFTWARE\Oracle\VirtualBox" -ErrorAction SilentlyContinue
$vboxManageCandidates = @(
    (Join-Path $InstallLocation "VBoxManage.exe"),
    "C:\Program Files\Oracle\VirtualBox\VBoxManage.exe"
)
if ($virtualBoxRegistry.InstallDir) {
    $vboxManageCandidates += Join-Path ([string]$virtualBoxRegistry.InstallDir) "VBoxManage.exe"
}
$vboxManage = $vboxManageCandidates | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } | Select-Object -First 1

if (-not $vboxManage) {
    throw "VirtualBox foi instalado, mas VBoxManage.exe nao foi localizado."
}

Write-Host "VirtualBox instalado: $vboxManage"
& $vboxManage --version

Write-Host "Reiniciando Multipass para carregar o ambiente do VirtualBox..."
Restart-Service -Name Multipass -Force
(Get-Service -Name Multipass).WaitForStatus(
    [System.ServiceProcess.ServiceControllerStatus]::Running,
    [TimeSpan]::FromSeconds(60)
)
Start-Sleep -Seconds 5

Write-Host "Trocando o driver do Multipass para VirtualBox..."
& $multipassExe set local.driver=virtualbox
if ($LASTEXITCODE -ne 0) {
    throw "Nao foi possivel configurar local.driver=virtualbox."
}

$driver = (& $multipassExe get local.driver | Out-String).Trim()
if ($driver -ne "virtualbox") {
    throw "Driver ativo inesperado: $driver"
}

Write-Host "Driver ativo: $driver"
& $multipassExe list

$rebuildParams = @{}
if ($ConfigureAptProxy) {
    $rebuildParams.ConfigureAptProxy = $true
}

Write-Host "Reconstruindo ia-lab no backend VirtualBox..."
& $rebuildScript @rebuildParams
