param(
    [string]$VmName = "ia-lab",
    [string]$Image = "24.04",
    [int]$Cpus = 4,
    [string]$Memory = "8G",
    [string]$Disk = "60G",
    [switch]$ConfigureAptProxy,
    [int]$ProxyPort = 18080,
    [string]$Passphrase
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
$backupRoot = Join-Path $repoRoot ("tmp\\multipass-reset-{0:yyyyMMdd_HHmmss}" -f (Get-Date))
$programData = "C:\ProgramData\Multipass"
$clientCertDir = Join-Path $env:LOCALAPPDATA "multipass-client-certificate"
$clientCertPath = Join-Path $clientCertDir "multipass_cert.pem"
$clientConfigDir = Join-Path $env:LOCALAPPDATA "Multipass"
$multipassExe = "C:\Program Files\Multipass\bin\multipass.exe"
$rebuildScript = Join-Path $PSScriptRoot "rebuild_multipass_vm.ps1"

if (-not (Test-Path -LiteralPath $multipassExe)) {
    throw "Multipass nao encontrado: $multipassExe"
}

if (-not (Test-Path -LiteralPath $rebuildScript)) {
    throw "Script de rebuild nao encontrado: $rebuildScript"
}

function Stop-MultipassServiceOrThrow {
    Write-Host "Parando servico Multipass..."
    $service = Get-Service -Name Multipass -ErrorAction SilentlyContinue
    if (-not $service -or $service.Status -eq "Stopped") {
        return
    }

    if ($service.Status -ne "StopPending") {
        sc.exe stop Multipass | Out-Host
    }

    try {
        $service.WaitForStatus(
            [System.ServiceProcess.ServiceControllerStatus]::Stopped,
            [TimeSpan]::FromSeconds(120)
        )
    }
    catch [System.ServiceProcess.TimeoutException] {
        $service.Refresh()
        $serviceProcess = Get-CimInstance Win32_Service -Filter "Name='Multipass'"
        $serviceInfo = sc.exe queryex Multipass | Out-String

        if ($service.Status -eq "StopPending" -and $serviceProcess.ProcessId -gt 0) {
            Write-Warning "Servico Multipass travado em STOP_PENDING. Encerrando somente o daemon PID $($serviceProcess.ProcessId)."
            Stop-Process -Id $serviceProcess.ProcessId -Force -ErrorAction Stop
            $service.WaitForStatus(
                [System.ServiceProcess.ServiceControllerStatus]::Stopped,
                [TimeSpan]::FromSeconds(30)
            )
            return
        }

        throw "Servico Multipass nao parou em 120 segundos (estado: $($service.Status)). Detalhes:`n$serviceInfo"
    }
}

function Start-MultipassService {
    Write-Host "Subindo servico Multipass..."
    $service = Get-Service -Name Multipass -ErrorAction Stop
    if ($service.Status -ne "Running") {
        sc.exe start Multipass | Out-Host
        $service.WaitForStatus(
            [System.ServiceProcess.ServiceControllerStatus]::Running,
            [TimeSpan]::FromSeconds(60)
        )
    }

    Start-Sleep -Seconds 3
}

function Invoke-MultipassAsSystem {
    param(
        [string]$Arguments,
        [string]$TaskNameSuffix
    )

    $taskName = "IA-LAB-Multipass-$TaskNameSuffix"
    $outputPath = Join-Path $backupRoot "$TaskNameSuffix.txt"
    $command = 'cmd.exe /c ""C:\Program Files\Multipass\bin\multipass.exe" ' + $Arguments + ' > "' + $outputPath + '" 2>&1"'

    $action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument ('-NoProfile -NonInteractive -Command ' + [char]34 + $command + [char]34)
    $trigger = New-ScheduledTaskTrigger -Once -At ((Get-Date).AddMinutes(1))
    $principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
    $settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -ExecutionTimeLimit (New-TimeSpan -Minutes 5)

    Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Force | Out-Null

    try {
        Start-ScheduledTask -TaskName $taskName

        for ($i = 0; $i -lt 30; $i++) {
            if (Test-Path -LiteralPath $outputPath) {
                break
            }

            Start-Sleep -Seconds 2
        }

        if (-not (Test-Path -LiteralPath $outputPath)) {
            throw "Nao houve saida da tarefa $taskName em tempo util."
        }

        return Get-Content -LiteralPath $outputPath -Raw
    }
    finally {
        Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue
    }
}

function Add-ClientCertificateToDaemonCandidates {
    if (-not (Test-Path -LiteralPath $clientCertPath)) {
        throw "Certificado do cliente nao encontrado: $clientCertPath"
    }

    $certContent = Get-Content -LiteralPath $clientCertPath -Raw
    $candidateFiles = @(
        "C:\ProgramData\Multipass\data\authenticated-certs\multipass_client_certs.pem",
        "C:\ProgramData\Multipass\data\multipassd\authenticated-certs\multipass_client_certs.pem"
    )

    foreach ($candidateFile in $candidateFiles) {
        $candidateDir = Split-Path -Parent $candidateFile
        New-Item -ItemType Directory -Path $candidateDir -Force | Out-Null

        if (Test-Path -LiteralPath $candidateFile) {
            $existing = Get-Content -LiteralPath $candidateFile -Raw
            if ($existing -like "*$($certContent.Trim())*") {
                Write-Host "Certificado do cliente ja presente em $candidateFile"
                continue
            }
        }

        Add-Content -LiteralPath $candidateFile -Value $certContent
        Write-Host "Certificado do cliente adicionado em $candidateFile"
    }
}

function Test-MultipassList {
    & $multipassExe list | Out-Null
    return ($LASTEXITCODE -eq 0)
}

New-Item -ItemType Directory -Path $backupRoot -Force | Out-Null

Write-Host "Backup de seguranca em $backupRoot"

if (Test-Path -LiteralPath $programData) {
    Copy-Item -LiteralPath $programData -Destination (Join-Path $backupRoot "ProgramData-Multipass-backup") -Recurse -Force
}

if (Test-Path -LiteralPath $clientCertDir) {
    Copy-Item -LiteralPath $clientCertDir -Destination (Join-Path $backupRoot "client-cert-backup") -Recurse -Force
}

if (Test-Path -LiteralPath $clientConfigDir) {
    Copy-Item -LiteralPath $clientConfigDir -Destination (Join-Path $backupRoot "client-config-backup") -Recurse -Force
}

Stop-MultipassServiceOrThrow

Write-Host "Limpando estado local do Multipass..."
if (Test-Path -LiteralPath $programData) {
    Remove-Item -LiteralPath $programData -Recurse -Force
}

if (Test-Path -LiteralPath $clientCertDir) {
    Remove-Item -LiteralPath $clientCertDir -Recurse -Force
}

if (Test-Path -LiteralPath $clientConfigDir) {
    Remove-Item -LiteralPath $clientConfigDir -Recurse -Force
}

Start-MultipassService

Write-Host "Validando cliente Multipass..."
& $multipassExe version

if (-not (Test-MultipassList)) {
    Write-Host "Cliente ainda nao autenticado. Aplicando bootstrap manual do certificado..."
    Stop-MultipassServiceOrThrow
    Add-ClientCertificateToDaemonCandidates
    Start-MultipassService
}

if (-not (Test-MultipassList) -and $Passphrase) {
    Write-Host "Cliente ainda nao autenticado. Tentando configurar local.passphrase como SYSTEM..."
    $systemOutput = Invoke-MultipassAsSystem -Arguments ("set local.passphrase=" + $Passphrase) -TaskNameSuffix "SetPassphrase"
    Write-Host ($systemOutput.Trim())
    Start-Sleep -Seconds 2
}

if (-not (Test-MultipassList) -and $Passphrase) {
    Write-Host "Tentando autenticar o cliente atual com a passphrase informada..."
    & $multipassExe authenticate $Passphrase
}

& $multipassExe list

if ($Passphrase -and (Test-MultipassList)) {
    Write-Host "Configurando local.passphrase no cliente atual para validar o pareamento..."
    & $multipassExe set "local.passphrase=$Passphrase"
}

$rebuildParams = @{
    VmName = $VmName
    Image = $Image
    Cpus = $Cpus
    Memory = $Memory
    Disk = $Disk
}

if ($ConfigureAptProxy) {
    $rebuildParams.ConfigureAptProxy = $true
    $rebuildParams.ProxyPort = $ProxyPort
}

Write-Host "Reconstruindo VM $VmName..."
& $rebuildScript @rebuildParams

Write-Host "Recriando portproxy e bootstrap da VM..."
& (Join-Path $repoRoot "scripts\\startup\\startup_vm.ps1")

Write-Host "Recriando tarefas agendadas..."
& (Join-Path $repoRoot "scripts\\setup\\configure_startup_tasks.ps1")
& (Join-Path $repoRoot "scripts\\setup\\configure_maintenance_tasks.ps1")

Write-Host "Fluxo concluido. Rode o healthcheck final:"
Write-Host "  D:\\IA-LAB\\scripts\\maintenance\\healthcheck.ps1"
