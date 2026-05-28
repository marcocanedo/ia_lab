$ErrorActionPreference = "Stop"

$vmName = "ia-lab"
$sshDir = Join-Path $env:USERPROFILE ".ssh"
$configPath = Join-Path $sshDir "config"
$keyPath = Join-Path $sshDir "ia_lab_ed25519"

New-Item -ItemType Directory -Force -Path $sshDir | Out-Null

if (-not (Test-Path $keyPath)) {
    ssh-keygen -t ed25519 -f $keyPath -N '""' -C "ia-lab-vscode" | Out-Null
}

$ipv4Line = multipass info $vmName | Select-String "^\s*IPv4:" | Select-Object -First 1
if (-not $ipv4Line) {
    throw "Nao foi possivel detectar IPv4 da VM $vmName"
}

$vmIp = (($ipv4Line.ToString() -split ":", 2)[1]).Trim()
if (-not $vmIp) {
    throw "IPv4 vazio para VM $vmName"
}

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
$bytes = [Text.Encoding]::UTF8.GetBytes($pub)
$b64 = [Convert]::ToBase64String($bytes)

multipass exec $vmName -- sh -lc "mkdir -p ~/.ssh && chmod 700 ~/.ssh && echo $b64 | base64 -d >> ~/.ssh/authorized_keys && sort -u ~/.ssh/authorized_keys -o ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys"

Write-Output "SSH config atualizado: ia-lab -> $vmIp"
