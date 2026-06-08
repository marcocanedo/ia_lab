$ErrorActionPreference = "Stop"

$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator
)

if (-not $isAdmin) {
    throw "Execute este script em um PowerShell aberto como Administrador."
}

$scriptRoot = "C:\IA-LAB\scripts\maintenance"
$currentTaskNames = @(
    "IA-LAB Watchdog",
    "IA-LAB Healthcheck",
    "IA-LAB Config Backup",
    "IA-LAB Multipass Snapshot",
    "IA-LAB Cleanup Logs"
)
$legacyScriptPaths = @(
    "C:\IA-LAB\scripts\watchdog.ps1",
    "C:\IA-LAB\scripts\healthcheck.ps1",
    "C:\IA-LAB\scripts\backup_configs.ps1",
    "C:\IA-LAB\scripts\snapshot_multipass.ps1",
    "C:\IA-LAB\scripts\cleanup_logs.ps1"
)

function Remove-IaLabLegacyMaintenanceTasks {
    $legacyTasks = Get-ScheduledTask -ErrorAction SilentlyContinue | Where-Object {
        $arguments = ($_.Actions | ForEach-Object { $_.Arguments }) -join " "
        $usesLegacyScript = $false

        foreach ($legacyScriptPath in $legacyScriptPaths) {
            if ($arguments -like "*$legacyScriptPath*") {
                $usesLegacyScript = $true
                break
            }
        }

        ($_.TaskName -in $currentTaskNames) -or $usesLegacyScript
    }

    foreach ($task in $legacyTasks) {
        if ($task.State -eq "Running") {
            Stop-ScheduledTask -TaskName $task.TaskName -TaskPath $task.TaskPath -ErrorAction SilentlyContinue
        }

        Unregister-ScheduledTask -TaskName $task.TaskName -TaskPath $task.TaskPath -Confirm:$false
    }
}

function Register-IaLabTask {
    param(
        [string]$Name,
        [string]$Script,
        [Microsoft.Management.Infrastructure.CimInstance]$Trigger,
        [string]$Description
    )

    $action = New-ScheduledTaskAction `
        -Execute "powershell.exe" `
        -Argument "-NoProfile -NonInteractive -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$scriptRoot\$Script`"" `
        -WorkingDirectory $scriptRoot

    $settings = New-ScheduledTaskSettingsSet `
        -MultipleInstances IgnoreNew `
        -StartWhenAvailable `
        -AllowStartIfOnBatteries `
        -DontStopIfGoingOnBatteries `
        -Hidden `
        -ExecutionTimeLimit (New-TimeSpan -Minutes 20)

    $principal = New-ScheduledTaskPrincipal `
        -UserId $env:USERNAME `
        -LogonType Interactive `
        -RunLevel Highest

    Register-ScheduledTask `
        -TaskName $Name `
        -Action $action `
        -Trigger $Trigger `
        -Settings $settings `
        -Principal $principal `
        -Description $Description `
        -Force | Out-Null
}

$watchdogTrigger = New-ScheduledTaskTrigger -Once -At (Get-Date).Date.AddMinutes(5) `
    -RepetitionInterval (New-TimeSpan -Minutes 5) `
    -RepetitionDuration (New-TimeSpan -Days 3650)

$healthTrigger = New-ScheduledTaskTrigger -Once -At (Get-Date).Date.AddMinutes(10) `
    -RepetitionInterval (New-TimeSpan -Minutes 15) `
    -RepetitionDuration (New-TimeSpan -Days 3650)

$backupTrigger = New-ScheduledTaskTrigger -Daily -At "22:00"
$snapshotTrigger = New-ScheduledTaskTrigger -Weekly -DaysOfWeek Sunday -At "23:00"
$cleanupTrigger = New-ScheduledTaskTrigger -Weekly -DaysOfWeek Sunday -At "23:30"

Remove-IaLabLegacyMaintenanceTasks

Register-IaLabTask "IA-LAB Watchdog" "watchdog.ps1" $watchdogTrigger "Reinicia componentes IA-LAB se PX, Ollama ou Open WebUI ficarem indisponiveis."
Register-IaLabTask "IA-LAB Healthcheck" "healthcheck.ps1" $healthTrigger "Gera relatorio de saude consolidado do IA-LAB."
Register-IaLabTask "IA-LAB Config Backup" "backup_configs.ps1" $backupTrigger "Backup diario de scripts, docs, compose, tarefas e estado operacional."
Register-IaLabTask "IA-LAB Multipass Snapshot" "snapshot_multipass.ps1" $snapshotTrigger "Snapshot semanal da VM Multipass ia-lab."
Register-IaLabTask "IA-LAB Cleanup Logs" "cleanup_logs.ps1" $cleanupTrigger "Remove logs e relatorios antigos conforme retencao padrao."

Get-ScheduledTask -TaskName "IA-LAB*" | Select-Object TaskName,State | Format-Table -AutoSize
