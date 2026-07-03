$ErrorActionPreference = "Stop"

$vmName = "ia-lab"
$sshDir = Join-Path $env:USERPROFILE ".ssh"
$configPath = Join-Path $sshDir "config"
$keyPath = Join-Path $sshDir "ia_lab_ed25519"

New-Item -ItemType Directory -Force -Path $sshDir | Out-Null

if (-not (Test-Path $keyPath)) {
    ssh-keygen -t ed25519 -f $keyPath -N '""' -C "ia-lab-vscode" | Out-Null
}

$vmIp = "localhost"

$config = @"
Host ia-lab
    HostName $vmIp
    User ubuntu
    IdentityFile $keyPath
    IdentitiesOnly yes
    StrictHostKeyChecking accept-new
"@

Set-Content -Encoding ASCII -Path $configPath -Value $config

$pub = Get-Content -Raw "$keyPath.pub"
wsl -d Ubuntu-24.04 -- bash -c "mkdir -p ~/.ssh && chmod 700 ~/.ssh && echo '$pub' >> ~/.ssh/authorized_keys && sort -u ~/.ssh/authorized_keys -o ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys"

Write-Output "SSH config atualizado: ia-lab -> localhost"
