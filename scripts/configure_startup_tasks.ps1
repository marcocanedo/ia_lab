$ErrorActionPreference = "Stop"

$taskName = "IA-LAB Startup"
$scriptPath = "C:\IA-LAB\scripts\startup_apps.ps1"
$workingDirectory = "C:\IA-LAB\scripts"

$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator
)

if (-not $isAdmin) {
    throw "Execute este script em um PowerShell aberto como Administrador."
}

if (-not (Test-Path $scriptPath)) {
    throw "Script nao encontrado: $scriptPath"
}

$action = New-ScheduledTaskAction `
    -Execute "powershell.exe" `
    -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$scriptPath`"" `
    -WorkingDirectory $workingDirectory

$startupTrigger = New-ScheduledTaskTrigger -AtStartup
$startupTrigger.Delay = "PT30S"

$logonTrigger = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME
$logonTrigger.Delay = "PT30S"

$settings = New-ScheduledTaskSettingsSet `
    -MultipleInstances IgnoreNew `
    -StartWhenAvailable `
    -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries `
    -ExecutionTimeLimit (New-TimeSpan -Minutes 10)

$principal = New-ScheduledTaskPrincipal `
    -UserId $env:USERNAME `
    -LogonType Interactive `
    -RunLevel Highest

Register-ScheduledTask `
    -TaskName $taskName `
    -Action $action `
    -Trigger $startupTrigger, $logonTrigger `
    -Settings $settings `
    -Principal $principal `
    -Description "Inicializa IA-LAB em ordem: PX, Ollama, VM ia-lab e portproxy do Open WebUI." `
    -Force | Out-Null

foreach ($oldTask in "IA-LAB PX Startup", "IA-LAB Ollama Startup", "IA-LAB Apps Startup") {
    $task = Get-ScheduledTask -TaskName $oldTask -ErrorAction SilentlyContinue
    if ($task) {
        Disable-ScheduledTask -TaskName $oldTask | Out-Null
    }
}

Get-ScheduledTask -TaskName $taskName, "IA-LAB PX Startup", "IA-LAB Ollama Startup", "IA-LAB Apps Startup" -ErrorAction SilentlyContinue |
    Select-Object TaskName, State |
    Format-Table -AutoSize
