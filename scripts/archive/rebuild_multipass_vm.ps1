param(
    [string]$VmName = "ia-lab",
    [string]$Image = "24.04",
    [int]$Cpus = 4,
    [string]$Memory = "8G",
    [string]$Disk = "60G",
    [switch]$DeleteExisting,
    [switch]$ConfigureAptProxy,
    [int]$ProxyPort = 18080,
    [switch]$SkipOpenWebUi,
    [switch]$SkipSshConfig
)

$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$dockerDir = Join-Path $repoRoot "docker"
$composePath = Join-Path $dockerDir "docker-compose.yml"
$envPath = Join-Path $dockerDir ".env"
$multipassExe = "C:\Program Files\Multipass\bin\multipass.exe"
$multipassImageCache = "D:\Multipass\cache\vault\images"
$vmComposeDir = "/home/ubuntu/ia-lab-docker"
$cloudInitPath = Join-Path $env:TEMP "ia-lab-cloud-init.yaml"

if (-not (Test-Path -LiteralPath $multipassExe)) {
    throw "Multipass nao encontrado: $multipassExe"
}

foreach ($requiredPath in @($composePath, $envPath)) {
    if (-not (Test-Path -LiteralPath $requiredPath)) {
        throw "Arquivo obrigatorio nao encontrado: $requiredPath"
    }
}

function Invoke-Multipass {
    param(
        [Parameter(ValueFromRemainingArguments = $true)]
        [string[]]$Arguments
    )

    # Windows PowerShell 5.1 can promote native stderr to a terminating ErrorRecord
    # when the script-wide preference is Stop. Capture it and handle the exit code here.
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
            throw "Cliente Multipass sem autenticacao. Repare o pareamento antes do rebuild com 'multipass authenticate <passphrase>' ou reprovisione o daemon."
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
package_update: true
packages:
  - docker.io
  - docker-compose-v2
  - openssh-server
  - curl
  - ca-certificates
runcmd:
  - systemctl enable --now docker
  - systemctl enable --now ssh
  - usermod -aG docker ubuntu
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
    Write-Host "Criando VM $VmName com imagem Ubuntu $Image..."
    $launchArguments = @(
        "launch", $Image,
        "--name", $VmName,
        "--cpus", $Cpus,
        "--memory", $Memory,
        "--disk", $Disk,
        "--cloud-init", $cloudInitPath
    )
    Invoke-MultipassLaunchWithCacheRetry -LaunchArguments $launchArguments
}
finally {
    Remove-Item -LiteralPath $cloudInitPath -Force -ErrorAction SilentlyContinue
}

Write-Host "Aguardando VM $VmName ficar Running..."
Wait-ForVmRunning -Name $VmName

if ($ConfigureAptProxy) {
    Write-Host "Configurando proxy APT na VM..."
    & (Join-Path $PSScriptRoot "configure_vm_proxy.ps1") -VmName $VmName -ProxyPort $ProxyPort
}

Write-Host "Preparando diretorio de compose na VM..."
Invoke-Multipass exec $VmName -- mkdir -p $vmComposeDir | Out-Null

Write-Host "Transferindo compose e .env para a VM..."
Invoke-Multipass transfer $composePath "${VmName}:${vmComposeDir}/docker-compose.yml" | Out-Null
Invoke-Multipass transfer $envPath "${VmName}:${vmComposeDir}/.env" | Out-Null
Invoke-Multipass exec $VmName -- sh -lc "chown ubuntu:ubuntu $vmComposeDir/docker-compose.yml $vmComposeDir/.env" | Out-Null

if (-not $SkipOpenWebUi) {
    Write-Host "Provisionando Open WebUI via Docker Compose..."
    Invoke-Multipass exec $VmName -- sh -lc "docker volume create open-webui >/dev/null && cd $vmComposeDir && docker compose config >/tmp/ia-lab-compose-config.txt && docker compose up -d open-webui" | Out-Null
    Invoke-Multipass exec $VmName -- docker ps | Out-Null
}

if (-not $SkipSshConfig) {
    Write-Host "Atualizando configuracao SSH local para VS Code Remote..."
    & (Join-Path $repoRoot "scripts\startup\update_ssh_config.ps1")
}

Write-Host "Validando VM..."
$vmInfo = Invoke-Multipass info $VmName
$dockerPs = Invoke-Multipass exec $VmName -- docker ps

Write-Output "VM reconstruida com sucesso."
Write-Output ($vmInfo | Out-String).Trim()

if (-not $SkipOpenWebUi) {
    Write-Output "Containers ativos:"
    Write-Output ($dockerPs | Out-String).Trim()
    Write-Output "Proximo passo no host: executar scripts\\startup\\startup_vm.ps1 em PowerShell elevado para recriar o portproxy 127.0.0.1:3000."
}
