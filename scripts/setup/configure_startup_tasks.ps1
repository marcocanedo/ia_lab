$ErrorActionPreference = "Stop"

$taskName = "IA-LAB WSL Boot"
$scriptsRoot = Split-Path -Parent $PSScriptRoot
$workingDirectory = Join-Path $scriptsRoot "startup"
$scriptPath = Join-Path $workingDirectory "startup_wsl.ps1"
$appsScriptPath = Join-Path $workingDirectory "startup_apps.ps1"

$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator
)

if (-not $isAdmin) {
    throw "Execute este script em um PowerShell aberto como Administrador."
}

if (-not (Test-Path $scriptPath)) {
    throw "Script nao encontrado: $scriptPath"
}

$settings = New-ScheduledTaskSettingsSet `
    -MultipleInstances IgnoreNew `
    -StartWhenAvailable `
    -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries `
    -Hidden `
    -ExecutionTimeLimit (New-TimeSpan -Minutes 10)

$wslAction = New-ScheduledTaskAction `
    -Execute "powershell.exe" `
    -Argument "-NoProfile -NonInteractive -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$scriptPath`"" `
    -WorkingDirectory $workingDirectory

$wslTrigger = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME
$wslTrigger.Delay = "PT30S"

$wslPrincipal = New-ScheduledTaskPrincipal `
    -UserId $env:USERNAME `
    -LogonType Interactive `
    -RunLevel Highest

Register-ScheduledTask `
    -TaskName $taskName `
    -Action $wslAction `
    -Trigger $wslTrigger `
    -Settings $settings `
    -Principal $wslPrincipal `
    -Description "Acorda distro WSL2 Ubuntu-24.04, garante Docker e Open WebUI em execucao." `
    -Force | Out-Null

foreach ($oldTask in "IA-LAB Startup", "IA-LAB PX Startup", "IA-LAB Ollama Startup", "IA-LAB Apps Startup", "IA-LAB Host Services", "IA-LAB VM Boot") {
    $task = Get-ScheduledTask -TaskName $oldTask -ErrorAction SilentlyContinue
    if ($task) {
        Unregister-ScheduledTask -TaskName $oldTask -Confirm:$false
    }
}

$appsAction = New-ScheduledTaskAction `
    -Execute "powershell.exe" `
    -Argument "-NoProfile -NonInteractive -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$appsScriptPath`"" `
    -WorkingDirectory $workingDirectory
$appsTrigger = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME
$appsTrigger.Delay = "PT20S"
$appsPrincipal = New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType Interactive -RunLevel Highest
Register-ScheduledTask -TaskName "IA-LAB Host Services" -Action $appsAction -Trigger $appsTrigger `
    -Settings $settings -Principal $appsPrincipal `
    -Description "Inicia PX, Ollama e roteador no logon do usuario." -Force | Out-Null

Get-ScheduledTask -TaskName $taskName, "IA-LAB Host Services" -ErrorAction SilentlyContinue |
    Select-Object TaskName, State |
    Format-Table -AutoSize
