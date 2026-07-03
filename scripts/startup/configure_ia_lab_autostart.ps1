$ErrorActionPreference = 'Stop'

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
$startupScript = Join-Path $scriptRoot 'startup_vm.ps1'
$userTaskName = 'IA-LAB Startup'
$bootTaskPath = '\IA-LAB Multipass Boot'
$bootTaskCommand = 'powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -WindowStyle Hidden -File "D:\IA-LAB\scripts\startup\startup_vm.ps1"'

if (-not (Test-Path $startupScript)) {
    throw "Script nao encontrado: $startupScript"
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
& schtasks.exe /Create /TN $bootTaskPath /SC ONSTART /RU SYSTEM /RL HIGHEST /TR $bootTaskCommand /F | Out-Null
if ($LASTEXITCODE -ne 0) {
    throw "Falha ao criar a tarefa de boot $bootTaskPath (codigo $LASTEXITCODE)"
}

Write-Host 'Habilitando a tarefa de boot...'
& schtasks.exe /Change /TN $bootTaskPath /ENABLE | Out-Null
if ($LASTEXITCODE -ne 0) {
    throw "Falha ao habilitar a tarefa de boot $bootTaskPath (codigo $LASTEXITCODE)"
}

Write-Host 'Habilitando a tarefa de logon existente...'
$userTask = Get-ScheduledTask -TaskName $userTaskName -ErrorAction SilentlyContinue
if ($userTask) {
    Enable-ScheduledTask -TaskName $userTaskName | Out-Null
}
else {
    Write-Warning "Tarefa $userTaskName nao encontrada. A VM ainda subira no boot via $bootTaskPath."
}

Write-Host 'Configuracao concluida.'
