$ErrorActionPreference = "Stop"

$vmName = "ia-lab"
$multipassExe = "C:\Program Files\Multipass\bin\multipass.exe"
$sshConfigScript = Join-Path $PSScriptRoot "update_ssh_config.ps1"

function Test-IsSystemAccount {
    return ([Security.Principal.WindowsIdentity]::GetCurrent().Name -eq "NT AUTHORITY\SYSTEM")
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
        [int]$TimeoutSeconds = 60
    )

    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    while ((Get-Date) -lt $deadline) {
        $info = & $script:MultipassExe info $Name 2>&1
        if ($LASTEXITCODE -eq 0) {
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

$script:MultipassExe = Get-MultipassExecutable

Write-Host "Aguardando o servico Multipass..."
Wait-ForMultipassService

$state = Get-MultipassState -Name $vmName
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

$vmIp = Get-VmIp -Name $vmName
if ($vmIp) {
    Write-Host "IP detectado: $vmIp"
}
else {
    Write-Warning "Nao foi possivel detectar o IP atual da VM $vmName."
}

if (-not (Test-IsSystemAccount) -and (Test-Path -LiteralPath $sshConfigScript)) {
    Write-Host "Atualizando configuracao SSH do host..."
    & $sshConfigScript -VmName $vmName -VmIp $vmIp
}
elseif (Test-IsSystemAccount) {
    Write-Host "Executando como SYSTEM; atualizacao do SSH do usuario sera feita no logon."
}

Write-Host "VM $vmName pronta."
