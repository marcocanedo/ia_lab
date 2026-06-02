param(
    [switch]$EnableAutoStart
)

$ErrorActionPreference = "Stop"
$taskName = "IA-LAB llama.cpp Startup"
$scriptPath = "C:\IA-LAB\scripts\llamacpp\start_all_llamacpp.ps1"

if (-not $EnableAutoStart) {
    Write-Host "Nenhuma tarefa foi registrada. Use -EnableAutoStart para criar a tarefa opcional $taskName."
    exit 0
}

$action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$scriptPath`""
$trigger = New-ScheduledTaskTrigger -AtLogOn
$principal = New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType Interactive -RunLevel Highest
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit (New-TimeSpan -Hours 8)

Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Description "Inicializacao opcional e sob demanda do llama.cpp no IA-LAB." -Force | Out-Null
Disable-ScheduledTask -TaskName $taskName | Out-Null

Write-Host "Tarefa criada desativada: $taskName"
