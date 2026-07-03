param(
    [string]$InstallerPath = "C:\Users\01481911775\Downloads\multipass-1.16.3+win-win64.msi"
)

$ErrorActionPreference = "Stop"

function Test-IsAdmin {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Wait-ProcessExit {
    param(
        [int]$ProcessId,
        [int]$TimeoutSeconds = 30
    )

    if ($ProcessId -le 0) {
        return
    }

    $process = Get-Process -Id $ProcessId -ErrorAction SilentlyContinue
    if (-not $process) {
        return
    }

    if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
        Stop-Process -Id $ProcessId -Force -ErrorAction Stop
        $process = Get-Process -Id $ProcessId -ErrorAction SilentlyContinue
        if ($process -and -not $process.WaitForExit(15000)) {
            throw "O processo Multipass PID $ProcessId nao encerrou apos o comando forcado."
        }
    }
}

if (-not (Test-IsAdmin)) {
    throw "Execute este script em PowerShell como Administrador."
}

if (-not (Test-Path -LiteralPath $InstallerPath -PathType Leaf)) {
    throw "Instalador do Multipass nao encontrado: $InstallerPath"
}

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$backupRoot = Join-Path $repoRoot ("tmp\multipass-clean-{0:yyyyMMdd_HHmmss}" -f (Get-Date))
$programDataPath = "C:\ProgramData\Multipass"
$clientPaths = @(
    (Join-Path $env:LOCALAPPDATA "Multipass"),
    (Join-Path $env:LOCALAPPDATA "multipass-client-certificate")
)
$storagePath = "D:\Multipass"
$badConfigPath = "D:\Multipassmultipassd.conf"
$multipassExe = "C:\Program Files\Multipass\bin\multipass.exe"

New-Item -ItemType Directory -Path $backupRoot -Force | Out-Null
Write-Host "Backup de seguranca em $backupRoot"

$backupItems = @($programDataPath) + $clientPaths + @($storagePath, $badConfigPath)
foreach ($item in $backupItems) {
    if (Test-Path -LiteralPath $item) {
        $backupName = ($item -replace '^[A-Za-z]:\\', '') -replace '[\\:]', '_'
        Copy-Item -LiteralPath $item -Destination (Join-Path $backupRoot $backupName) -Recurse -Force
    }
}

Write-Host "Parando o daemon Multipass..."
$service = Get-CimInstance Win32_Service -Filter "Name='Multipass'" -ErrorAction SilentlyContinue
if ($service) {
    if ($service.State -notin @("Stopped", "Stop Pending")) {
        sc.exe stop Multipass | Out-Host
    }

    if ($service.ProcessId -gt 0) {
        Wait-ProcessExit -ProcessId $service.ProcessId -TimeoutSeconds 30
    }
}

Write-Host "Desinstalando Multipass..."
$uninstallKeys = @(
    "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*",
    "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*"
)
$product = Get-ItemProperty $uninstallKeys -ErrorAction SilentlyContinue |
    Where-Object { $_.DisplayName -like "Multipass*" } |
    Select-Object -First 1

if ($product -and $product.PSChildName -match '^\{[0-9A-Fa-f-]+\}$') {
    $uninstall = Start-Process msiexec.exe -ArgumentList @("/x", $product.PSChildName, "/qn", "/norestart") -Wait -PassThru
    if ($uninstall.ExitCode -notin @(0, 1605, 3010)) {
        throw "A desinstalacao do Multipass falhou com codigo $($uninstall.ExitCode)."
    }
}
else {
    Write-Warning "Produto MSI Multipass nao encontrado; continuando com a limpeza do estado residual."
}

$remainingService = Get-CimInstance Win32_Service -Filter "Name='Multipass'" -ErrorAction SilentlyContinue
if ($remainingService) {
    if ($remainingService.ProcessId -gt 0) {
        Wait-ProcessExit -ProcessId $remainingService.ProcessId -TimeoutSeconds 10
    }
    sc.exe delete Multipass | Out-Host
}

Write-Host "Removendo somente o estado do Multipass..."
$cleanupPaths = @($programDataPath) + $clientPaths + @($storagePath, $badConfigPath)
foreach ($item in $cleanupPaths) {
    if (Test-Path -LiteralPath $item) {
        Remove-Item -LiteralPath $item -Recurse -Force
    }
}

Remove-Item -LiteralPath "HKCU:\Software\Canonical\Multipass" -Recurse -Force -ErrorAction SilentlyContinue
[Environment]::SetEnvironmentVariable("MULTIPASS_STORAGE", $storagePath, "Machine")
$env:MULTIPASS_STORAGE = $storagePath
New-Item -ItemType Directory -Path $storagePath -Force | Out-Null

Write-Host "Reinstalando Multipass em estado limpo..."
$install = Start-Process msiexec.exe -ArgumentList @("/i", $InstallerPath, "/qn", "/norestart") -Wait -PassThru
if ($install.ExitCode -notin @(0, 3010)) {
    throw "A instalacao do Multipass falhou com codigo $($install.ExitCode)."
}

if (-not (Test-Path -LiteralPath $multipassExe -PathType Leaf)) {
    throw "Multipass nao foi encontrado apos a reinstalacao: $multipassExe"
}

$serviceController = Get-Service -Name Multipass -ErrorAction Stop
if ($serviceController.Status -ne "Running") {
    Start-Service -Name Multipass
    $serviceController.WaitForStatus(
        [System.ServiceProcess.ServiceControllerStatus]::Running,
        [TimeSpan]::FromSeconds(60)
    )
}

Start-Sleep -Seconds 5
Write-Host "Validando cliente novo..."
& $multipassExe version
& $multipassExe list
if ($LASTEXITCODE -ne 0) {
    throw "A reinstalacao terminou, mas o cliente ainda nao foi autenticado. Backup: $backupRoot"
}

Write-Host "Multipass reinstalado e autenticado. Armazenamento: $storagePath"
Write-Host "Proximo passo: D:\IA-LAB\scripts\setup\rebuild_multipass_vm.ps1 -ConfigureAptProxy"
