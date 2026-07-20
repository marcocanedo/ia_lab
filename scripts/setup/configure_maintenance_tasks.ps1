$ErrorActionPreference = "Stop"

$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator
)

if (-not $isAdmin) {
    throw "Execute este script em um PowerShell aberto como Administrador."
}

$scriptRoot = Join-Path (Split-Path -Parent $PSScriptRoot) "maintenance"
$currentTaskNames = @(
    "IA-LAB Watchdog",
    "IA-LAB Healthcheck",
    "IA-LAB Config Backup",
    "IA-LAB Cleanup Logs"
)
$legacyScriptPaths = @()

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

$watchdogTrigger = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(15) `
    -RepetitionInterval (New-TimeSpan -Minutes 15) `
    -RepetitionDuration (New-TimeSpan -Days 3650)

$healthTrigger = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(30) `
    -RepetitionInterval (New-TimeSpan -Minutes 60) `
    -RepetitionDuration (New-TimeSpan -Days 3650)

$cleanupTrigger = New-ScheduledTaskTrigger -Weekly -DaysOfWeek Sunday -At "23:30"

Remove-IaLabLegacyMaintenanceTasks

Register-IaLabTask "IA-LAB Watchdog" "watchdog.ps1" $watchdogTrigger "Reinicia PX e a VM base se algum deles ficar indisponivel."
Register-IaLabTask "IA-LAB Healthcheck" "healthcheck.ps1" $healthTrigger "Gera relatorio de saude consolidado do PX, Multipass e da VM base."
Register-IaLabTask "IA-LAB Cleanup Logs" "cleanup_logs.ps1" $cleanupTrigger "Remove logs e relatorios antigos conforme retencao padrao."

Get-ScheduledTask -TaskName "IA-LAB*" | Select-Object TaskName,State | Format-Table -AutoSize
