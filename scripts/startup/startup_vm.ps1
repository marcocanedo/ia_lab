$ErrorActionPreference = "Stop"

$vmName = "ia-lab"
$listenPort = 3000
$connectPort = 3000

function Test-IsSystemAccount {
    return ([Security.Principal.WindowsIdentity]::GetCurrent().Name -eq "NT AUTHORITY\SYSTEM")
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
            try {
                $null = multipass list 2>$null
                return
            }
            catch {
                Start-Sleep -Seconds 2
                continue
            }
        }

        if ($service.Status -ne $lastStatus) {
            Write-Host "Servico Multipass esta $($service.Status). Aguardando inicializacao..."
            $lastStatus = $service.Status
        }

        try {
            Start-Service -Name Multipass -ErrorAction Stop
        }
        catch {
            # O boot task pode rodar antes do servico ficar pronto ou sem token elevado.
            # Nesse caso, apenas aguardamos o Windows concluir a inicializacao do servico.
        }

        Start-Sleep -Seconds 2
    }

    throw "Servico Multipass nao ficou disponivel em $TimeoutSeconds segundos"
}

function Get-MultipassState {
    param(
        [string]$Name
    )

    try {
        $stateLine = multipass list | Select-String ("^\s*{0}\s+" -f [regex]::Escape($Name)) | Select-Object -First 1
    }
    catch {
        return $null
    }

    if (-not $stateLine) {
        return $null
    }

    $tokens = $stateLine.ToString().Trim() -split "\s+"
    if ($tokens.Count -ge 2) {
        return $tokens[1]
    }

    return $null
}

Write-Host "Aguardando o servico Multipass ficar disponivel..."
Wait-ForMultipassService

Write-Host "Iniciando VM $vmName..."

$state = Get-MultipassState $vmName
if ($state -eq "Running") {
    Write-Host "VM $vmName ja esta Running."
}
else {
    multipass start $vmName
}

Write-Host "Aguardando VM ficar Running..."
for ($i = 1; $i -le 60; $i++) {
    $state = Get-MultipassState $vmName
    if ($state -eq "Running") {
        break
    }
    Start-Sleep -Seconds 2
}

if ((Get-MultipassState $vmName) -ne "Running") {
    throw "VM $vmName nao entrou em estado Running"
}

Write-Host "Obtendo IP da VM..."

$vmIp = $null
for ($i = 1; $i -le 30; $i++) {
    $ipv4Line = multipass info $vmName | Select-String "^\s*IPv4:" | Select-Object -First 1
    if ($ipv4Line) {
        $vmIp = (($ipv4Line.ToString() -split ":", 2)[1]).Trim()
    }

    if ($vmIp) {
        break
    }

    Start-Sleep -Seconds 2
}

if (-not $vmIp) {
    throw "Nao foi possivel detectar o IP da VM $vmName"
}

Write-Host "IP detectado: $vmIp"

if (-not (Test-IsSystemAccount)) {
    $sshUpdateScript = Join-Path $PSScriptRoot "update_ssh_config.ps1"
    if (Test-Path $sshUpdateScript) {
        Write-Host "Atualizando SSH config para VSCode Remote..."
        & $sshUpdateScript
    }
}
else {
    Write-Host "Executando como SYSTEM; pulando atualizacao do SSH config do usuario."
}

Write-Host "Atualizando portproxy..."

netsh interface portproxy delete v4tov4 listenaddress=127.0.0.1 listenport=$listenPort | Out-Null

netsh interface portproxy add v4tov4 `
    listenaddress=127.0.0.1 `
    listenport=$listenPort `
    connectaddress=$vmIp `
    connectport=$connectPort

$proxy = netsh interface portproxy show v4tov4
$expectedProxy = $proxy | Select-String "127\.0\.0\.1\s+$listenPort\s+$([regex]::Escape($vmIp))\s+$connectPort"
if (-not $expectedProxy) {
    throw "Portproxy 127.0.0.1:$listenPort -> ${vmIp}:$connectPort nao foi configurado"
}

Write-Host "Aguardando Open WebUI em 127.0.0.1:$listenPort..."
for ($i = 1; $i -le 60; $i++) {
    $ready = Test-NetConnection 127.0.0.1 -Port $listenPort -InformationLevel Quiet
    if ($ready) {
        Write-Host "Open WebUI acessivel em http://127.0.0.1:$listenPort"
        return
    }
    Start-Sleep -Seconds 2
}

throw "Open WebUI nao respondeu na porta $listenPort"
