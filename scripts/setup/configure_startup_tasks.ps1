$ErrorActionPreference = "Stop"

function Test-IsAdministrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Invoke-Sc {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Arguments
    )

    & sc.exe @Arguments | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw "Falha ao executar sc.exe $($Arguments -join ' ') (codigo $LASTEXITCODE)"
    }
}

if (-not (Test-IsAdministrator)) {
    $arguments = @(
        '-NoProfile',
        '-NonInteractive',
        '-ExecutionPolicy',
        'Bypass',
        '-File',
        $PSCommandPath
    )

    Start-Process -FilePath 'powershell.exe' -Verb RunAs -ArgumentList $arguments
    exit
}

$scriptRoot = Split-Path -Parent $PSCommandPath
$startupRoot = Join-Path $scriptRoot 'startup'
$bootScript = Join-Path $startupRoot 'startup_vm.ps1'
$hostServicesScript = Join-Path $startupRoot 'startup_apps.ps1'
$bootTaskName = 'IA-LAB VM Boot'
$hostServicesTaskName = 'IA-LAB Host Services'
$bootTaskCommand = 'powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -WindowStyle Hidden -File "D:\IA-LAB\scripts\startup\startup_vm.ps1"'

foreach ($requiredScript in @($bootScript, $hostServicesScript)) {
    if (-not (Test-Path -LiteralPath $requiredScript)) {
        throw "Script nao encontrado: $requiredScript"
    }
}

Write-Host 'Configurando o servico Multipass para iniciar automaticamente...'
Invoke-Sc -Arguments @('config', 'Multipass', 'start=', 'auto')
Invoke-Sc -Arguments @('failureflag', 'Multipass', '1')
Invoke-Sc -Arguments @('failure', 'Multipass', 'reset=', '86400', 'actions=', 'restart/5000/restart/5000/restart/5000')

try {
    $service = Get-Service -Name Multipass -ErrorAction Stop
    if ($service.Status -ne 'Running') {
        Write-Host 'Iniciando o servico Multipass...'
        Start-Service -Name Multipass
    }
}
catch {
    Write-Warning "Nao foi possivel iniciar o servico Multipass imediatamente: $($_.Exception.Message)"
}

Write-Host 'Criando tarefa de boot para subir a VM ao iniciar o Windows...'
& schtasks.exe /Create /TN $bootTaskName /SC ONSTART /RU SYSTEM /RL HIGHEST /TR $bootTaskCommand /F | Out-Null
if ($LASTEXITCODE -ne 0) {
    throw "Falha ao criar a tarefa de boot $bootTaskName (codigo $LASTEXITCODE)"
}

Write-Host 'Habilitando a tarefa de boot...'
& schtasks.exe /Change /TN $bootTaskName /ENABLE | Out-Null
if ($LASTEXITCODE -ne 0) {
    throw "Falha ao habilitar a tarefa de boot $bootTaskName (codigo $LASTEXITCODE)"
}

Write-Host 'Registrando a tarefa de logon para os servicos base...'
$settings = New-ScheduledTaskSettingsSet `
    -MultipleInstances IgnoreNew `
    -StartWhenAvailable `
    -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries `
    -Hidden `
    -ExecutionTimeLimit (New-TimeSpan -Minutes 10)

$action = New-ScheduledTaskAction `
    -Execute "powershell.exe" `
    -Argument "-NoProfile -NonInteractive -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$hostServicesScript`"" `
    -WorkingDirectory $startupRoot

$trigger = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME
$trigger.Delay = "PT20S"

$principal = New-ScheduledTaskPrincipal `
    -UserId $env:USERNAME `
    -LogonType Interactive `
    -RunLevel Highest

Register-ScheduledTask `
    -TaskName $hostServicesTaskName `
    -Action $action `
    -Trigger $trigger `
    -Settings $settings `
    -Principal $principal `
    -Description "Inicia PX e revalida a VM base do IA-LAB no logon do usuario." `
    -Force | Out-Null

foreach ($oldTask in "IA-LAB Startup", "IA-LAB PX Startup", "IA-LAB Apps Startup", "IA-LAB WSL Boot", "IA-LAB Multipass Boot") {
    $task = Get-ScheduledTask -TaskName $oldTask -ErrorAction SilentlyContinue
    if ($task) {
        Unregister-ScheduledTask -TaskName $oldTask -Confirm:$false
    }
}

Get-ScheduledTask -TaskName $bootTaskName, $hostServicesTaskName -ErrorAction SilentlyContinue |
    Select-Object TaskName, State |
    Format-Table -AutoSize
