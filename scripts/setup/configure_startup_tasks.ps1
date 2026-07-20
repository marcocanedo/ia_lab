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

$scriptRoot = Split-Path -Parent $PSScriptRoot
$startupRoot = Join-Path $scriptRoot 'startup'
$bootScript = Join-Path $startupRoot 'startup_vm.ps1'
$hostServicesScript = Join-Path $startupRoot 'startup_apps.ps1'
$sshDir = Join-Path $env:USERPROFILE '.ssh'
$bootTaskName = 'IA-LAB VM Boot'
$hostServicesTaskName = 'IA-LAB Host Services'
$bootTaskCommand = 'powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -WindowStyle Hidden -File "D:\IA-LAB\scripts\startup\startup_vm.ps1" -SshDir "{0}"' -f $sshDir
$bootTaskDelay = '0000:30'
$pxFirewallRuleName = 'IA-LAB PX Virtual Networks'
$pxHyperVRuleName = 'IA-LAB PX WSL'
$pxMultipassInterfaceAlias = 'vEthernet (Default Switch)'
$wslVmCreatorId = '{40E0AC32-46A5-438A-A0B2-2B479E8F2E90}'

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

Write-Host 'Liberando a porta do PX somente para as redes virtuais locais...'
$pxFirewallRule = Get-NetFirewallRule -DisplayName $pxFirewallRuleName -ErrorAction SilentlyContinue
if ($pxFirewallRule) {
    $pxFirewallRule | Set-NetFirewallRule -Enabled True -Direction Inbound -Action Allow -Profile Any
    $pxFirewallRule | Get-NetFirewallAddressFilter | Set-NetFirewallAddressFilter -RemoteAddress LocalSubnet
    $pxFirewallRule | Get-NetFirewallInterfaceFilter | Set-NetFirewallInterfaceFilter -InterfaceAlias $pxMultipassInterfaceAlias
    $pxFirewallRule | Get-NetFirewallPortFilter | Set-NetFirewallPortFilter -Protocol TCP -LocalPort 18080
}
else {
    New-NetFirewallRule `
        -DisplayName $pxFirewallRuleName `
        -Direction Inbound `
        -Action Allow `
        -Enabled True `
        -Profile Any `
        -Protocol TCP `
        -LocalPort 18080 `
        -RemoteAddress LocalSubnet `
        -InterfaceAlias $pxMultipassInterfaceAlias | Out-Null
}

if (Get-Command Get-NetFirewallHyperVRule -ErrorAction SilentlyContinue) {
    $pxHyperVRule = Get-NetFirewallHyperVRule -Name $pxHyperVRuleName -ErrorAction SilentlyContinue
    if ($pxHyperVRule) {
        $pxHyperVRule | Set-NetFirewallHyperVRule `
            -Enabled True `
            -Direction Inbound `
            -Action Allow `
            -VMCreatorId $wslVmCreatorId `
            -Protocol TCP `
            -LocalPorts 18080 | Out-Null
    }
    else {
        New-NetFirewallHyperVRule `
            -Name $pxHyperVRuleName `
            -DisplayName $pxHyperVRuleName `
            -Enabled True `
            -Direction Inbound `
            -Action Allow `
            -VMCreatorId $wslVmCreatorId `
            -Protocol TCP `
            -LocalPorts 18080 | Out-Null
    }
}

Write-Host 'Criando tarefa de boot para subir a VM ao iniciar o Windows...'
& schtasks.exe /Create /TN $bootTaskName /SC ONSTART /DELAY $bootTaskDelay /RU SYSTEM /RL HIGHEST /TR $bootTaskCommand /F | Out-Null
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
$trigger.Delay = "PT30S"

$principal = New-ScheduledTaskPrincipal `
    -UserId $env:USERNAME `
    -LogonType Interactive `
    -RunLevel Limited

Register-ScheduledTask `
    -TaskName $hostServicesTaskName `
    -Action $action `
    -Trigger $trigger `
    -Settings $settings `
    -Principal $principal `
    -Description "Inicia PX e sincroniza a VM base do IA-LAB no logon do usuario sem reiniciar a VM." `
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
