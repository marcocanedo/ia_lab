param(
    [switch]$LogonOnly,
    [string]$SshDir
)

$ErrorActionPreference = "Stop"

$vmName = "ia-lab"
$multipassExe = "C:\Program Files\Multipass\bin\multipass.exe"
$sshConfigScript = Join-Path $PSScriptRoot "update_ssh_config.ps1"
$vscodeProxyScript = Join-Path (Split-Path $PSScriptRoot -Parent) "setup\configure_vscode_remote_proxy.sh"

function Test-IsSystemAccount {
    return ([Security.Principal.WindowsIdentity]::GetCurrent().User.Value -eq "S-1-5-18")
}

if (Test-IsSystemAccount) {
    $bootLogDir = Join-Path (Split-Path $PSScriptRoot -Parent) "logs"
    New-Item -ItemType Directory -Path $bootLogDir -Force | Out-Null
    $bootLogFile = Join-Path $bootLogDir ("startup_vm_system_{0:yyyyMMdd_HHmmss}.log" -f (Get-Date))
    Start-Transcript -Path $bootLogFile -Append | Out-Null
}

function Get-MultipassExecutable {
    if (Test-Path -LiteralPath $multipassExe) {
        return $multipassExe
    }

    $command = Get-Command multipass -ErrorAction SilentlyContinue
    if ($command) {
        return $command.Source
    }

    throw "Multipass nao encontrado. Instale o cliente Multipass antes de iniciar a VM."
}

function Invoke-Multipass {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Arguments
    )

    $output = & $script:MultipassExe @Arguments 2>&1
    $exitCode = $LASTEXITCODE
    if ($exitCode -ne 0) {
        $message = ($output | Out-String).Trim()
        throw "Falha ao executar multipass $($Arguments -join ' '): $message"
    }

    return $output
}

function Wait-ForMultipassService {
    param(
        [int]$TimeoutSeconds = 120
    )

    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    $lastStatus = $null

    while ((Get-Date) -lt $deadline) {
        $service = Get-Service -Name Multipass -ErrorAction SilentlyContinue
        if (-not $service) {
            throw "Servico Multipass nao encontrado."
        }

        if ($service.Status -eq "Running") {
            return
        }

        if ($service.Status -ne $lastStatus) {
            Write-Host "Servico Multipass esta $($service.Status). Aguardando inicializacao..."
            $lastStatus = $service.Status
        }

        try {
            Start-Service -Name Multipass -ErrorAction Stop
        }
        catch {
            # Se o script nao tiver privilegio ou o service controller ainda estiver iniciando,
            # continuamos aguardando ate o timeout.
        }

        Start-Sleep -Seconds 2
    }

    throw "Servico Multipass nao ficou disponivel em $TimeoutSeconds segundos"
}

function Test-MultipassReady {
    $previousErrorActionPreference = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    try {
        $output = & $script:MultipassExe list 2>&1
        $exitCode = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $previousErrorActionPreference
    }

    if ($exitCode -ne 0) {
        $message = ($output | Out-String).Trim()
        if ($message -and $message -ne $script:LastMultipassReadyError) {
            Write-Host "multipass list falhou: $message"
            $script:LastMultipassReadyError = $message
        }
    }

    return ($exitCode -eq 0)
}

function Wait-ForMultipassReady {
    param(
        [int]$TimeoutSeconds = 180
    )

    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    $loggedWaiting = $false

    while ((Get-Date) -lt $deadline) {
        if (Test-MultipassReady) {
            return
        }

        if (-not $loggedWaiting) {
            Write-Host "Multipass ainda nao responde aos comandos. Aguardando..."
            $loggedWaiting = $true
        }

        Start-Sleep -Seconds 2
    }

    throw "Multipass nao ficou pronto para comandos em $TimeoutSeconds segundos"
}

function Test-MultipassServiceRunning {
    $service = Get-Service -Name Multipass -ErrorAction SilentlyContinue
    return ($service -and $service.Status -eq "Running")
}

function Get-MultipassState {
    param(
        [string]$Name
    )

    $stateLine = & $script:MultipassExe list | Select-String ("^\s*{0}\s+" -f [regex]::Escape($Name)) | Select-Object -First 1
    if (-not $stateLine) {
        return $null
    }

    $tokens = $stateLine.ToString().Trim() -split "\s+"
    if ($tokens.Count -lt 2) {
        return $null
    }

    return $tokens[1]
}

function Wait-ForVmListed {
    param(
        [string]$Name,
        [int]$TimeoutSeconds = 180
    )

    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    $loggedWaiting = $false

    while ((Get-Date) -lt $deadline) {
        $state = Get-MultipassState -Name $Name
        if ($state) {
            return $state
        }

        if (-not $loggedWaiting) {
            Write-Host "VM $Name ainda nao apareceu no multipass list. Aguardando..."
            $loggedWaiting = $true
        }

        Start-Sleep -Seconds 2
    }

    return $null
}

function Wait-ForVmRunning {
    param(
        [string]$Name,
        [int]$TimeoutSeconds = 180
    )

    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    while ((Get-Date) -lt $deadline) {
        if ((Get-MultipassState -Name $Name) -eq "Running") {
            return
        }

        Start-Sleep -Seconds 3
    }

    throw "VM $Name nao entrou em estado Running em $TimeoutSeconds segundos"
}

function Get-VmIp {
    param(
        [string]$Name,
        [int]$TimeoutSeconds = 15
    )

    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    while ((Get-Date) -lt $deadline) {
        $previousErrorActionPreference = $ErrorActionPreference
        $ErrorActionPreference = "Continue"
        try {
            $info = & $script:MultipassExe info $Name 2>&1
            $exitCode = $LASTEXITCODE
        }
        finally {
            $ErrorActionPreference = $previousErrorActionPreference
        }

        if ($exitCode -eq 0) {
            $ipv4Line = $info | Select-String "^\s*IPv4:" | Select-Object -First 1
            if ($ipv4Line) {
                $value = (($ipv4Line.ToString() -split ":", 2)[1]).Trim()
                if ($value) {
                    return ($value -split "\s+")[0]
                }
            }
        }

        Start-Sleep -Seconds 2
    }

    return $null
}

function Sync-VmProxy {
    param([string]$Name)

    $command = @'
gateway=$(ip route show default | awk '{print $3; exit}')
test -n "$gateway"
printf 'Acquire::http::Proxy "http://%s:18080";\nAcquire::https::Proxy "http://%s:18080";\n' "$gateway" "$gateway" | sudo tee /etc/apt/apt.conf.d/95proxy >/dev/null
'@

    try {
        Invoke-Multipass -Arguments @("exec", $Name, "--", "sh", "-lc", $command) | Out-Null
        Write-Host "Proxy APT sincronizado com o gateway atual da VM."
    }
    catch {
        Write-Warning "Nao foi possivel sincronizar o proxy APT: $($_.Exception.Message)"
    }
}

function Sync-VscodeRemoteProxy {
    param([string]$Name)

    if (-not (Test-Path -LiteralPath $vscodeProxyScript)) {
        Write-Warning "Script do proxy remoto do VS Code nao encontrado: $vscodeProxyScript"
        return
    }

    try {
        Invoke-Multipass -Arguments @("transfer", $vscodeProxyScript, "${Name}:/tmp/configure_vscode_remote_proxy.sh") | Out-Null
        Invoke-Multipass -Arguments @("exec", $Name, "--", "bash", "/tmp/configure_vscode_remote_proxy.sh", "18080") | Out-Null
        Write-Host "Proxy do VS Code Server/Codex sincronizado com o gateway atual da VM."
    }
    catch {
        Write-Warning "Nao foi possivel sincronizar o proxy do VS Code Server/Codex: $($_.Exception.Message)"
    }
}

function Sync-SshConfig {
    param(
        [string]$Name,
        [string]$VmIp,
        [string]$SshDir
    )

    if (-not (Test-Path -LiteralPath $sshConfigScript)) {
        Write-Warning "Script de SSH nao encontrado: $sshConfigScript"
        return $false
    }

    $sshArguments = @{
        VmName = $Name
        VmIp = $VmIp
    }

    if ($SshDir) {
        $sshArguments.SshDir = $SshDir
    }

    try {
        & $sshConfigScript @sshArguments | Out-Null
        Write-Host "Configuracao SSH sincronizada com o IP atual da VM."
        return $true
    }
    catch {
        Write-Warning "Nao foi possivel sincronizar a configuracao SSH: $($_.Exception.Message)"
        return $false
    }
}

$script:MultipassExe = Get-MultipassExecutable

if (Test-IsSystemAccount) {
    Write-Host "Boot SYSTEM: garantindo apenas o servico Multipass; o bootstrap da VM e o SSH serao feitos no logon do usuario."
    Wait-ForMultipassService -TimeoutSeconds 120
    Write-Host "Servico Multipass pronto."
    return
}

if ($LogonOnly) {
    Write-Host "Modo leve de logon: sincronizando apenas se a VM ja estiver pronta."

    try {
        Wait-ForMultipassService -TimeoutSeconds 120
    }
    catch {
        Write-Host "Servico Multipass nao ficou pronto no logon; sincronizacao leve ignorada."
        return
    }

    try {
        Wait-ForMultipassReady -TimeoutSeconds 90
    }
    catch {
        Write-Host "Multipass ainda nao ficou pronto no logon; sincronizacao leve ignorada."
        return
    }

    $state = Wait-ForVmListed -Name $vmName -TimeoutSeconds 90
    if (-not $state) {
        Write-Host "VM $vmName nao encontrada; sincronizacao leve ignorada."
        return
    }

    if ($state -ne "Running") {
        Write-Host "VM $vmName esta $state; aguardando ficar Running..."
        try {
            Wait-ForVmRunning -Name $vmName -TimeoutSeconds 180
        }
        catch {
            Write-Host "VM $vmName nao ficou Running a tempo; sincronizacao leve ignorada."
            return
        }
    }

    $vmIp = Get-VmIp -Name $vmName -TimeoutSeconds 30
    if ($vmIp) {
        Write-Host "IP detectado: $vmIp"
    }
    else {
        Write-Warning "Nao foi possivel detectar o IP atual da VM $vmName; sincronizacao SSH ignorada."
        return
    }

    Sync-VmProxy -Name $vmName
    Sync-VscodeRemoteProxy -Name $vmName

    if (Test-IsSystemAccount -and -not $SshDir) {
        Write-Host "Executando como SYSTEM; a sincronizacao SSH do usuario acontece no logon."
        return
    }

    Write-Host "Sincronizando SSH do usuario para $vmName..."
    if (-not (Sync-SshConfig -Name $vmName -VmIp $vmIp -SshDir $SshDir)) {
        return
    }

    Write-Host "VM $vmName pronta para o logon."
    return
}

Write-Host "Aguardando o servico Multipass..."
Wait-ForMultipassService
Wait-ForMultipassReady

$state = Wait-ForVmListed -Name $vmName
if (-not $state) {
    throw "VM $vmName nao encontrada. Execute scripts\setup\rebuild_multipass_vm.ps1 para cria-la."
}

if ($state -eq "Running") {
    Write-Host "VM $vmName ja esta Running."
}
else {
    Write-Host "Iniciando VM $vmName..."
    Invoke-Multipass -Arguments @("start", $vmName) | Out-Null
}

Wait-ForVmRunning -Name $vmName
Sync-VmProxy -Name $vmName
Sync-VscodeRemoteProxy -Name $vmName

$vmIp = Get-VmIp -Name $vmName
if ($vmIp) {
    Write-Host "IP detectado: $vmIp"
}
else {
    Write-Warning "Nao foi possivel detectar o IP atual da VM $vmName; sincronizacao SSH ignorada."
}

if ($vmIp -and ((-not (Test-IsSystemAccount)) -or $SshDir) -and (Test-Path -LiteralPath $sshConfigScript)) {
    Write-Host "Atualizando configuracao SSH do host..."
    $sshStdout = Join-Path $env:TEMP ("ia-lab-ssh-sync-{0}.out" -f ([guid]::NewGuid().ToString("N")))
    $sshStderr = Join-Path $env:TEMP ("ia-lab-ssh-sync-{0}.err" -f ([guid]::NewGuid().ToString("N")))

    try {
        $sshArguments = @(
            "-NoProfile",
            "-NonInteractive",
            "-ExecutionPolicy",
            "Bypass",
            "-File",
            $sshConfigScript,
            "-VmName",
            $vmName,
            "-VmIp",
            $vmIp
        )

        if ($SshDir) {
            $sshArguments += @("-SshDir", $SshDir)
        }

        $sshProcess = Start-Process `
            -FilePath "powershell.exe" `
            -ArgumentList $sshArguments `
            -RedirectStandardOutput $sshStdout `
            -RedirectStandardError $sshStderr `
            -Wait `
            -PassThru `
            -WindowStyle Hidden

        if ($sshProcess.ExitCode -ne 0) {
            Write-Warning "Falha ao atualizar a configuracao SSH: processo retornou codigo $($sshProcess.ExitCode)."
            if (Test-Path -LiteralPath $sshStderr) {
                $sshError = (Get-Content -LiteralPath $sshStderr -Raw).Trim()
                if ($sshError) {
                    Write-Warning $sshError
                }
            }
        }
    }
    catch {
        Write-Warning "Falha ao atualizar a configuracao SSH: $($_.Exception.Message)"
    }
    finally {
        Remove-Item -LiteralPath $sshStdout, $sshStderr -Force -ErrorAction SilentlyContinue
    }

    $global:LASTEXITCODE = 0
}
elseif (Test-IsSystemAccount) {
    Write-Host "Executando como SYSTEM; atualizacao do SSH do usuario sera feita no logon."
}

Write-Host "VM $vmName pronta."
