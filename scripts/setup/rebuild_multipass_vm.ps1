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
$multipassExe = "C:\Program Files\Multipass\bin\multipass.exe"
$cloudInitPath = Join-Path $env:TEMP ("ia-lab-cloud-init-{0}.yaml" -f $VmName)

if (-not (Test-Path -LiteralPath $multipassExe)) {
    throw "Multipass nao encontrado: $multipassExe"
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
  - openssh-server
  - curl
  - ca-certificates
runcmd:
  - systemctl enable --now ssh
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

Write-Host "Configurando proxy APT da VM para usar PX..."
$pxListening = Test-NetConnection 127.0.0.1 -Port $ProxyPort -InformationLevel Quiet
if (-not $pxListening) {
    Write-Host "PX nao esta escutando em 127.0.0.1:$ProxyPort. Executando startup_px.ps1..."
    & (Join-Path $repoRoot "scripts\startup\startup_px.ps1")
}

& (Join-Path $PSScriptRoot "configure_vm_proxy.ps1") -VmName $VmName -ProxyPort $ProxyPort

Write-Host "Executando apt-get update via PX..."
Invoke-Multipass exec $VmName -- sh -lc "sudo DEBIAN_FRONTEND=noninteractive apt-get update"

if ($BootstrapOnly) {
    Write-Output "Bootstrap concluido: VM criada, proxy APT configurado e apt-get update validado."
    return
}

Write-Host "Garantindo o servico SSH na VM..."
Invoke-Multipass exec $VmName -- sh -lc "sudo systemctl enable --now ssh >/dev/null 2>&1 || true"

if (-not $SkipSshConfig) {
    Write-Host "Atualizando configuracao SSH local para VS Code Remote..."
    & (Join-Path $repoRoot "scripts\startup\update_ssh_config.ps1") -VmName $VmName
}

Write-Host "Validando VM..."
$vmInfo = Invoke-Multipass info $VmName
$sshStatus = Invoke-Multipass exec $VmName -- sh -lc "systemctl is-active ssh 2>/dev/null || true"

Write-Output "VM reconstruida com sucesso."
Write-Output ($vmInfo | Out-String).Trim()
Write-Output ("SSH na VM: {0}" -f (($sshStatus | Out-String).Trim()))
