param(
    [switch]$ConfigureAptProxy,
    [int]$ProxyPort = 18080
)

$ErrorActionPreference = "Stop"

$distroName = "Ubuntu-24.04"
$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$dockerDir = Join-Path $repoRoot "docker"
$composePath = Join-Path $dockerDir "docker-compose.yml"
$envPath = Join-Path $dockerDir ".env"

function Test-IsAdmin {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

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

function Invoke-WslCommand {
    param(
        [string]$Distro,
        [string]$Command
    )

    $output = wsl -d $Distro -- sh -lc $Command 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "Comando WSL falhou: $Command`n$output"
    }

    return $output
}

if (-not (Test-IsAdmin)) {
    throw "Execute este script em PowerShell como Administrador."
}

if (-not (Test-WslAvailable)) {
    throw "WSL2 nao esta disponivel. Verifique se o recurso esta habilitado no Windows."
}

foreach ($requiredPath in @($composePath, $envPath)) {
    if (-not (Test-Path -LiteralPath $requiredPath)) {
        throw "Arquivo obrigatorio nao encontrado: $requiredPath"
    }
}

Write-Host "Garantindo .wslconfig com localhostForwarding=true e vmIdleTimeout=-1..."
$wslConfigPath = "$env:USERPROFILE\.wslconfig"
$wslConfigContent = "[wsl2]`nlocalhostForwarding=true`nvmIdleTimeout=-1`n"
if (-not (Test-Path $wslConfigPath)) {
    $wslConfigContent | Out-File -Encoding ASCII -FilePath $wslConfigPath
    Write-Host ".wslconfig criado."
}
else {
    $existing = Get-Content $wslConfigPath -Raw
    if ($existing.Trim() -ne $wslConfigContent.Trim()) {
        $wslConfigContent | Out-File -Encoding ASCII -FilePath $wslConfigPath
        Write-Host ".wslconfig atualizado."
    }
    else {
        Write-Host ".wslconfig ja esta configurado."
    }
}

Write-Host "Verificando se a distro $distroName ja existe..."
$installedDistros = wsl -l -q 2>$null | ForEach-Object { $_.Trim() }
if ($installedDistros -notcontains $distroName) {
    Write-Host "Instalando distro $distroName..."
    wsl --install -d $distroName --no-launch
    if ($LASTEXITCODE -ne 0) {
        throw "Falha ao instalar distro $distroName"
    }
}

Write-Host "Aguardando distro ficar disponivel..."
Wait-ForDistro -Name $distroName

# Detectar gateway WSL2 (IP do Windows acessivel de dentro da distro)
$gatewayIp = (wsl -d $distroName -u root -- bash -c "ip route show default | grep -oP '(?<=via )[0-9.]+'" 2>$null).Trim()
if (-not $gatewayIp) {
    throw "Nao foi possivel detectar o gateway WSL2. Verifique se a distro tem acesso a rede."
}
$proxyUrl = "http://${gatewayIp}:$ProxyPort"
Write-Host "Gateway WSL2 detectado: $gatewayIp (proxy: $proxyUrl)"

Write-Host "Configurando proxy APT e ambiente na distro..."
$setupScript = @"
#!/bin/bash
set -e

# Proxy APT (sempre necessario em rede corporativa)
mkdir -p /etc/apt/apt.conf.d
cat > /etc/apt/apt.conf.d/95proxy << APTEOF
Acquire::http::Proxy "$proxyUrl";
Acquire::https::Proxy "$proxyUrl";
APTEOF

# Proxy ambiente
cat > /etc/environment << ENVEOF
http_proxy=$proxyUrl
https_proxy=$proxyUrl
HTTP_PROXY=$proxyUrl
HTTPS_PROXY=$proxyUrl
NO_PROXY=localhost,127.0.0.1
no_proxy=localhost,127.0.0.1
ENVEOF

# Proxy daemon Docker
mkdir -p /etc/systemd/system/docker.service.d
cat > /etc/systemd/system/docker.service.d/proxy.conf << DOCKEOF
[Service]
Environment="HTTP_PROXY=$proxyUrl"
Environment="HTTPS_PROXY=$proxyUrl"
Environment="NO_PROXY=localhost,127.0.0.1"
DOCKEOF

echo "Proxy configurado para gateway $gatewayIp"
"@
$setupScript | Out-File -Encoding ASCII -FilePath "$env:TEMP\wsl-proxy-setup.sh"
wsl -d $distroName -u root -- bash /mnt/c/Users/$env:USERNAME/AppData/Local/Temp/wsl-proxy-setup.sh
Remove-Item -Path "$env:TEMP\wsl-proxy-setup.sh" -Force -ErrorAction SilentlyContinue

Write-Host "Provisionando pacotes basicos na distro..."
Invoke-WslCommand -Distro $distroName -Command "apt-get update -y && apt-get install -y docker.io docker-compose-v2 openssh-server curl ca-certificates"

Write-Host "Configurando usuario ubuntu no grupo docker..."
Invoke-WslCommand -Distro $distroName -Command "id ubuntu 2>/dev/null || useradd -m -s /bin/bash ubuntu; usermod -aG docker ubuntu"

Write-Host "Criando diretorio de compose..."
Invoke-WslCommand -Distro $distroName -Command "mkdir -p /home/ubuntu/ia-lab-docker && chown ubuntu:ubuntu /home/ubuntu/ia-lab-docker"

Write-Host "Criando script de boot da distro..."
$bootScriptPath = "/usr/local/bin/ia-lab-wsl-boot.sh"
$bootScript = @"
#!/bin/sh
set -eu

service docker start >/dev/null 2>&1 || true
nohup sh -c 'while true; do sleep 3600; done' >/dev/null 2>&1 &
"@
$bootScript | Out-File -Encoding ASCII -FilePath "$env:TEMP\ia-lab-wsl-boot.sh"
wsl -d $distroName -u root -- bash -c "mkdir -p /usr/local/bin && cp /mnt/c/Users/$env:USERNAME/AppData/Local/Temp/ia-lab-wsl-boot.sh $bootScriptPath && chmod 755 $bootScriptPath"
Remove-Item -Path "$env:TEMP\ia-lab-wsl-boot.sh" -Force -ErrorAction SilentlyContinue

Write-Host "Criando /etc/wsl.conf..."
$wslConf = "[boot]`nsystemd=true`ncommand=$bootScriptPath`n`n[user]`ndefault=ubuntu`n"
$wslConf | Out-File -Encoding ASCII -FilePath "$env:TEMP\wsl.conf"
wsl -d $distroName -u root -- bash -c "cp /mnt/c/Users/$env:USERNAME/AppData/Local/Temp/wsl.conf /etc/wsl.conf"
Remove-Item -Path "$env:TEMP\wsl.conf" -Force -ErrorAction SilentlyContinue

Write-Host "Transferindo compose e .env para a distro..."
wsl -d $distroName -- mkdir -p /home/ubuntu/ia-lab-docker
wsl -d $distroName -- cp "/mnt/c/$($composePath.Replace('\', '/'))" /home/ubuntu/ia-lab-docker/docker-compose.yml
wsl -d $distroName -- cp "/mnt/c/$($envPath.Replace('\', '/'))" /home/ubuntu/ia-lab-docker/.env
Invoke-WslCommand -Distro $distroName -Command "chown ubuntu:ubuntu /home/ubuntu/ia-lab-docker/docker-compose.yml /home/ubuntu/ia-lab-docker/.env"

Write-Host "Reiniciando distro para aplicar /etc/wsl.conf..."
wsl --terminate $distroName

Write-Host "Aguardando distro voltar..."
Wait-ForDistro -Name $distroName

Write-Host "Habilitando Docker para iniciar automaticamente dentro da distro..."
Invoke-WslCommand -Distro $distroName -Command "systemctl enable docker >/dev/null 2>&1 || true"

Write-Host "Iniciando Docker e provisionando Open WebUI..."
Invoke-WslCommand -Distro $distroName -Command "service docker start && docker volume create open-webui >/dev/null && cd /home/ubuntu/ia-lab-docker && docker compose up -d open-webui"

Write-Host "Atualizando configuracao SSH local para VS Code Remote..."
& (Join-Path $repoRoot "scripts\startup\update_ssh_config.ps1")

Write-Host "Validando containers..."
$dockerPs = Invoke-WslCommand -Distro $distroName -Command "docker ps"
Write-Output ($dockerPs | Out-String).Trim()

Write-Host "Distro WSL2 $distroName provisionada com sucesso."
