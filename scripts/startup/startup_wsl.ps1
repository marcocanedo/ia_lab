$ErrorActionPreference = "Stop"

$distroName = "Ubuntu-24.04"
$listenPort = 3000
$vmComposeDir = "/home/ubuntu/ia-lab-docker"
$wslConfigPath = Join-Path $env:USERPROFILE ".wslconfig"

function Test-WslAvailable {
    try {
        $null = wsl.exe --version 2>$null
        return $true
    }
    catch {
        return $false
    }
}

function Wait-ForDistro {
    param(
        [string]$Name,
        [int]$TimeoutSeconds = 120
    )

    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    while ((Get-Date) -lt $deadline) {
        try {
            $null = wsl -d $Name -- true 2>$null
            return
        }
        catch {
            Start-Sleep -Seconds 2
        }
    }

    throw "Distro WSL2 $Name nao respondeu em $TimeoutSeconds segundos"
}

function Get-WslNetworkingMode {
    if (-not (Test-Path -LiteralPath $wslConfigPath)) {
        return "default"
    }

    $content = Get-Content -LiteralPath $wslConfigPath -Raw
    if ($content -match '(?im)^\s*networkingMode\s*=\s*mirrored\s*$') {
        return "mirrored"
    }

    return "default"
}

function Ensure-OpenWebUiContainer {
    param(
        [string]$Distro
    )

    $containerStatus = $null
    try {
        $containerStatus = (wsl -d $Distro -- sh -lc "docker inspect -f '{{.State.Status}}' open-webui 2>/dev/null").Trim()
    }
    catch {
        $containerStatus = $null
    }

    if (-not $containerStatus) {
        Write-Host "Container open-webui ausente. Recriando via Docker Compose..."
        $composeCheck = wsl -d $Distro -- sh -lc "test -f $vmComposeDir/docker-compose.yml && test -f $vmComposeDir/.env"
        if ($LASTEXITCODE -ne 0) {
            throw "Compose do Open WebUI nao encontrado em $vmComposeDir. Execute scripts\setup\provision_wsl_distro.ps1 para provisionar a distro."
        }

        wsl -d $Distro -- sh -lc "docker volume create open-webui >/dev/null 2>&1 || true; cd $vmComposeDir && docker compose up -d open-webui"
        if ($LASTEXITCODE -ne 0) {
            throw "Falha ao recriar open-webui via Docker Compose em $vmComposeDir"
        }

        return
    }

    if ($containerStatus -eq "running") {
        Write-Host "Container open-webui ja esta running."
        return
    }

    Write-Host "Container open-webui esta $containerStatus. Iniciando..."
    wsl -d $Distro -- sh -lc "docker start open-webui >/dev/null"
    if ($LASTEXITCODE -ne 0) {
        throw "Falha ao iniciar o container open-webui"
    }
}

function Set-WslPortProxy {
    param(
        [string]$Distro,
        [int]$Port
    )

    $wslIp = (wsl -d $Distro -- sh -lc "ip -4 addr show eth0 2>/dev/null | awk '/inet / {print \$2}' | cut -d/ -f1 | head -n 1" 2>$null).Trim()
    if (-not $wslIp) {
        $wslIp = (wsl -d $Distro -- sh -lc "hostname -I | awk '{print \$1}'" 2>$null).Trim()
    }

    if (-not $wslIp) {
        Write-Host "Aviso: nao foi possivel detectar IP da distro WSL2. Portproxy nao criado."
        return
    }

    netsh interface portproxy delete v4tov4 listenaddress=127.0.0.1 listenport=$Port 2>$null | Out-Null
    netsh interface portproxy add v4tov4 listenaddress=127.0.0.1 listenport=$Port connectaddress=$wslIp connectport=$Port | Out-Null
    Write-Host "Portproxy: 127.0.0.1:$Port -> ${wslIp}:$Port"
}

function Test-WslKeepAlive {
    param(
        [string]$Distro
    )

    # Reuse the stored dbus session pid so repeated startups do not spawn duplicates.
    $checkScript = 'if [ -f /tmp/ia-lab-wsl-keepalive.pid ] && pgrep -F /tmp/ia-lab-wsl-keepalive.pid >/dev/null 2>&1; then exit 0; fi; exit 1'
    wsl -d $Distro -- sh -lc $checkScript | Out-Null
    return ($LASTEXITCODE -eq 0)
}

function Start-WslKeepAlive {
    param(
        [string]$Distro
    )

    if (Test-WslKeepAlive -Distro $Distro) {
        Write-Host "Keepalive WSL via dbus-launch ja esta ativo."
        return
    }

    Write-Host "Ativando keepalive WSL via dbus-launch..."
    $launchOutput = wsl -d $Distro -- sh -lc 'dbus-launch --sh-syntax'
    if ($LASTEXITCODE -ne 0) {
        Write-Warning "Falha ao ativar keepalive WSL via dbus-launch."
        return
    }

    $dbusPid = $null
    if (($launchOutput -join [Environment]::NewLine) -match 'DBUS_SESSION_BUS_PID=([0-9]+)') {
        $dbusPid = $Matches[1]
    }

    if (-not $dbusPid) {
        Write-Warning "dbus-launch nao retornou o PID da sessao."
        return
    }

    wsl -d $Distro -- sh -lc "printf '%s\n' $dbusPid > /tmp/ia-lab-wsl-keepalive.pid" | Out-Null
    if ($LASTEXITCODE -ne 0) {
        Write-Warning "Keepalive WSL iniciado, mas nao foi possivel gravar o PID da sessao."
        return
    }

    Write-Host "Keepalive WSL ativado."
}

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not (Test-WslAvailable)) {
    throw "WSL2 nao esta disponivel. Verifique se o recurso esta habilitado no Windows."
}

$networkingMode = Get-WslNetworkingMode
Write-Host "WSL networking mode: $networkingMode"

Write-Host "Acordando distro WSL2 $distroName..."
wsl -d $distroName -u root -- systemctl start docker 2>$null | Out-Null

Write-Host "Aguardando distro responder..."
Wait-ForDistro -Name $distroName

Start-WslKeepAlive -Distro $distroName

Write-Host "Habilitando Docker para iniciar automaticamente nas proximas inicializacoes da distro..."
wsl -d $distroName -u root -- sh -lc "systemctl enable docker >/dev/null 2>&1 || true" | Out-Null

Write-Host "Garantindo que o container open-webui esteja em execucao..."
Ensure-OpenWebUiContainer -Distro $distroName

Write-Host "Atualizando SSH config para VSCode Remote..."
& (Join-Path $PSScriptRoot "update_ssh_config.ps1")

if ($isAdmin) {
    if ($networkingMode -eq "mirrored") {
        Write-Host "WSL mirrored networking detectado. Removendo portproxy local antigo, se existir..."
        netsh interface portproxy delete v4tov4 listenaddress=127.0.0.1 listenport=$listenPort 2>$null | Out-Null
    }
    else {
        Write-Host "Atualizando portproxy 127.0.0.1:$listenPort -> WSL2..."
        Set-WslPortProxy -Distro $distroName -Port $listenPort
    }
}
else {
    if ($networkingMode -eq "mirrored") {
        Write-Host "Aviso: sem privilegio de Administrador - portproxy nao removido, mas localhostForwarding deve ser suficiente."
    }
    else {
        Write-Host "Aviso: sem privilegio de Administrador - portproxy nao atualizado. Execute como Admin ou use o localhostForwarding do WSL2."
    }
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
