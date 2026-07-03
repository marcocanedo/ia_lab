param(
    [string]$VmName = "ia-lab",
    [string]$Image = "24.04",
    [int]$Cpus = 8,
    [string]$Memory = "16G",
    [string]$Disk = "120G",
    [switch]$DeleteExisting,
    [switch]$BootstrapOnly,
    [switch]$SkipSshConfig,
    [int]$ProxyPort = 18080
)

$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$dockerDir = Join-Path $repoRoot "docker"
$composePath = Join-Path $dockerDir "docker-compose.yml"
$envPath = Join-Path $dockerDir ".env"
$multipassExe = "C:\Program Files\Multipass\bin\multipass.exe"
$vmComposeDir = "/home/ubuntu/ia-lab-docker"
$cloudInitPath = Join-Path $env:TEMP ("ia-lab-cloud-init-{0}.yaml" -f $VmName)

if (-not (Test-Path -LiteralPath $multipassExe)) {
    throw "Multipass nao encontrado: $multipassExe"
}

if (-not $BootstrapOnly) {
    foreach ($requiredPath in @($composePath, $envPath)) {
        if (-not (Test-Path -LiteralPath $requiredPath)) {
            throw "Arquivo obrigatorio nao encontrado: $requiredPath"
        }
    }
}

function Invoke-Multipass {
    param(
        [Parameter(ValueFromRemainingArguments = $true)]
        [string[]]$Arguments
    )

    $previousErrorActionPreference = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    try {
        $output = & $multipassExe @Arguments 2>&1
        $exitCode = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $previousErrorActionPreference
    }

    if ($exitCode -ne 0) {
        $message = ($output | Out-String).Trim()
        if ($message -match "not authenticated") {
            throw "Cliente Multipass sem autenticacao. Repare o pareamento antes de continuar com 'multipass authenticate <passphrase>'."
        }

        throw "Falha ao executar multipass $($Arguments -join ' '): $message"
    }

    return $output
}

function Get-MultipassState {
    param(
        [string]$Name
    )

    $listOutput = Invoke-Multipass list
    $stateLine = $listOutput | Select-String ("^\s*{0}\s+" -f [regex]::Escape($Name)) | Select-Object -First 1
    if (-not $stateLine) {
        return $null
    }

    $tokens = $stateLine.ToString().Trim() -split "\s+"
    if ($tokens.Count -lt 2) {
        return $null
    }

    return $tokens[1]
}

function Invoke-MultipassLaunchWithCacheRetry {
    param(
        [string[]]$LaunchArguments
    )

    try {
        Invoke-Multipass @LaunchArguments | Out-Null
        return
    }
    catch {
        $message = $_.Exception.Message
        $match = [regex]::Match($message, 'Hash of\s+(.+?\.img)\s+does not match', 'IgnoreCase')
        if (-not $match.Success) {
            throw
        }

        $multipassImageCache = "D:\Multipass\cache\vault\images"
        $imagePath = $match.Groups[1].Value.Trim() -replace '/', '\'
        $cacheRoot = [IO.Path]::GetFullPath($multipassImageCache).TrimEnd('\')
        $fullImagePath = [IO.Path]::GetFullPath($imagePath)
        if (-not $fullImagePath.StartsWith($cacheRoot + '\', [StringComparison]::OrdinalIgnoreCase)) {
            throw "Multipass informou imagem corrompida fora do cache permitido: $fullImagePath"
        }

        $corruptVersionPath = Split-Path -Parent $fullImagePath
        Write-Warning "Cache de imagem corrompido. Removendo $corruptVersionPath e repetindo o download uma vez."
        Remove-Item -LiteralPath $corruptVersionPath -Recurse -Force -ErrorAction Stop
        Invoke-Multipass @LaunchArguments | Out-Null
    }
}

function Invoke-MultipassExec {
    param(
        [string]$Name,
        [string[]]$Command
    )

    Invoke-Multipass (@("exec", $Name, "--") + $Command)
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

function New-CloudInitFile {
    $cloudInit = @"
#cloud-config
package_update: false
package_upgrade: false
runcmd:
  - mkdir -p /home/ubuntu/ia-lab-docker
  - chown -R ubuntu:ubuntu /home/ubuntu/ia-lab-docker
"@

    Set-Content -LiteralPath $cloudInitPath -Value $cloudInit -Encoding ASCII
}

Invoke-Multipass version | Out-Null
Invoke-Multipass list | Out-Null

$existingState = Get-MultipassState -Name $VmName
if ($existingState) {
    if (-not $DeleteExisting) {
        throw "VM $VmName ja existe com estado $existingState. Use -DeleteExisting para recriar do zero."
    }

    if ($existingState -eq "Running") {
        Write-Host "Parando VM existente $VmName..."
        Invoke-Multipass stop $VmName | Out-Null
    }

    Write-Host "Deletando VM existente $VmName..."
    Invoke-Multipass delete $VmName | Out-Null
    Invoke-Multipass purge | Out-Null
}

New-CloudInitFile

try {
    Write-Host "Criando VM $VmName com Ubuntu $Image e configuracao confortavel..."
    $launchArguments = @(
        "launch", $Image,
        "--name", $VmName,
        "--cpus", $Cpus,
        "--memory", $Memory,
        "--disk", $Disk,
        "--cloud-init", $cloudInitPath
    )
    Invoke-MultipassLaunchWithCacheRetry -LaunchArguments $launchArguments

    Write-Host "Aguardando VM $VmName ficar Running..."
    Wait-ForVmRunning -Name $VmName

    Write-Host "Configurando proxy APT da VM para usar PX..."
    & (Join-Path $PSScriptRoot "configure_vm_proxy.ps1") -VmName $VmName -ProxyPort $ProxyPort

    Write-Host "Validando arquivo de proxy dentro da VM..."
    Invoke-MultipassExec -Name $VmName -Command @("sh", "-lc", "cat /etc/apt/apt.conf.d/95proxy")

    Write-Host "Executando apt-get update via PX..."
    Invoke-MultipassExec -Name $VmName -Command @("sh", "-lc", "sudo DEBIAN_FRONTEND=noninteractive apt-get update")

    if ($BootstrapOnly) {
        Write-Output "Bootstrap concluido: VM criada, proxy APT configurado e apt-get update validado."
        return
    }

    Write-Host "Instalando pacote base para Docker e SSH..."
    Invoke-MultipassExec -Name $VmName -Command @("sh", "-lc", "sudo DEBIAN_FRONTEND=noninteractive apt-get install -y docker.io docker-compose-v2 openssh-server curl ca-certificates")

    Write-Host "Habilitando Docker e SSH..."
    Invoke-MultipassExec -Name $VmName -Command @("sh", "-lc", "sudo systemctl enable --now docker ssh")
    Invoke-MultipassExec -Name $VmName -Command @("sh", "-lc", "sudo usermod -aG docker ubuntu")

    Write-Host "Preparando diretorio de compose na VM..."
    Invoke-MultipassExec -Name $VmName -Command @("mkdir", "-p", $vmComposeDir) | Out-Null

    Write-Host "Transferindo compose e .env para a VM..."
    Invoke-Multipass transfer $composePath "${VmName}:${vmComposeDir}/docker-compose.yml" | Out-Null
    Invoke-Multipass transfer $envPath "${VmName}:${vmComposeDir}/.env" | Out-Null
    Invoke-MultipassExec -Name $VmName -Command @("sh", "-lc", "chown ubuntu:ubuntu $vmComposeDir/docker-compose.yml $vmComposeDir/.env") | Out-Null

    Write-Host "Subindo o Open WebUI via Docker Compose..."
    Invoke-MultipassExec -Name $VmName -Command @("sh", "-lc", "sudo docker volume create open-webui >/dev/null && cd $vmComposeDir && sudo docker compose up -d open-webui")
    Invoke-MultipassExec -Name $VmName -Command @("sh", "-lc", "sudo docker ps") | Out-Null

    if (-not $SkipSshConfig) {
        Write-Host "Atualizando configuracao SSH local para VS Code Remote..."
        & (Join-Path $repoRoot "scripts\startup\update_ssh_config.ps1")
    }

    Write-Host "Validando VM..."
    $vmInfo = Invoke-Multipass info $VmName
    $dockerPs = Invoke-MultipassExec -Name $VmName -Command @("sudo", "docker", "ps")

    Write-Output "VM reconstruida com sucesso."
    Write-Output ($vmInfo | Out-String).Trim()
    Write-Output "Containers ativos:"
    Write-Output ($dockerPs | Out-String).Trim()
    Write-Output "Proximo passo no host: recriar o portproxy 127.0.0.1:3000 com o script de startup correspondente."
}
finally {
    Remove-Item -LiteralPath $cloudInitPath -Force -ErrorAction SilentlyContinue
}
