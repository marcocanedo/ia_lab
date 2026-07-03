param(
    [string]$VmName = "ia-lab",
    [string]$VmIp
)

$ErrorActionPreference = "Stop"

$multipassExe = "C:\Program Files\Multipass\bin\multipass.exe"
$sshDir = Join-Path $env:USERPROFILE ".ssh"
$configPath = Join-Path $sshDir "config"
$keyPath = Join-Path $sshDir "ia_lab_ed25519"

function Get-MultipassExecutable {
    if (Test-Path -LiteralPath $multipassExe) {
        return $multipassExe
    }

    $command = Get-Command multipass -ErrorAction SilentlyContinue
    if ($command) {
        return $command.Source
    }

    throw "Multipass nao encontrado."
}

function Get-VmIp {
    param([string]$Name)

    $info = & $script:MultipassExe info $Name 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "Nao foi possivel obter informacoes da VM $Name."
    }

    $ipv4Line = $info | Select-String "^\s*IPv4:" | Select-Object -First 1
    if (-not $ipv4Line) {
        return $null
    }

    $value = (($ipv4Line.ToString() -split ":", 2)[1]).Trim()
    if (-not $value) {
        return $null
    }

    return ($value -split "\s+")[0]
}

$script:MultipassExe = Get-MultipassExecutable

if (-not $VmIp) {
    $VmIp = Get-VmIp -Name $VmName
}

if (-not $VmIp) {
    throw "Nao foi possivel detectar o IP atual da VM $VmName."
}

New-Item -ItemType Directory -Force -Path $sshDir | Out-Null

if (-not (Test-Path -LiteralPath $keyPath)) {
    ssh-keygen -t ed25519 -f $keyPath -N '' -C "ia-lab" | Out-Null
}

$publicKeyPath = "$keyPath.pub"
if (-not (Test-Path -LiteralPath $publicKeyPath)) {
    throw "Chave publica nao encontrada em $publicKeyPath"
}

$publicKey = (Get-Content -LiteralPath $publicKeyPath -Raw).Trim()
$remoteCommand = "set -e; mkdir -p ~/.ssh; chmod 700 ~/.ssh; printf '%s\n' '$publicKey' >> ~/.ssh/authorized_keys; sort -u ~/.ssh/authorized_keys -o ~/.ssh/authorized_keys; chmod 600 ~/.ssh/authorized_keys; (sudo systemctl enable --now ssh >/dev/null 2>&1 || systemctl enable --now ssh >/dev/null 2>&1 || true)"

& $script:MultipassExe exec $VmName -- sh -lc $remoteCommand | Out-Null
if ($LASTEXITCODE -ne 0) {
    throw "Falha ao atualizar authorized_keys da VM $VmName."
}

$config = @"
Host $VmName
    HostName $VmIp
    User ubuntu
    Port 22
    IdentityFile $keyPath
    IdentitiesOnly yes
    StrictHostKeyChecking accept-new
"@

Set-Content -Encoding ASCII -Path $configPath -Value $config

Write-Output "SSH config atualizado: $VmName -> $VmIp"
