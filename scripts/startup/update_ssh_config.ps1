param(
    [string]$VmName = "ia-lab",
    [string]$VmIp,
    [string[]]$PreferredIpPrefixes = @("172.19.164.", "10.13.31."),
    [string]$SshDir,
    [switch]$SkipKeyInjection
)

$ErrorActionPreference = "Stop"

$multipassExe = "C:\Program Files\Multipass\bin\multipass.exe"
$sshDir = if ($SshDir) { $SshDir } else { Join-Path $env:USERPROFILE ".ssh" }
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
    param(
        [string]$Name,
        [string[]]$PreferredPrefixes
    )

    $info = & $script:MultipassExe info $Name 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "Nao foi possivel obter informacoes da VM $Name."
    }

    $ipv4Candidates = New-Object System.Collections.Generic.List[string]
    foreach ($ipv4Line in ($info | Select-String "^\s*IPv4:")) {
        foreach ($match in [regex]::Matches($ipv4Line.ToString(), '\b(?:\d{1,3}\.){3}\d{1,3}\b')) {
            if (-not $ipv4Candidates.Contains($match.Value)) {
                $ipv4Candidates.Add($match.Value)
            }
        }
    }

    if ($ipv4Candidates.Count -eq 0) {
        return $null
    }

    foreach ($prefix in $PreferredPrefixes) {
        $preferred = $ipv4Candidates | Where-Object { $_ -like "$prefix*" } | Select-Object -First 1
        if ($preferred) {
            return $preferred
        }
    }

    return $ipv4Candidates[0]
}

function Test-SshKeyAccess {
    param(
        [string]$HostName
    )

    if (-not (Get-Command ssh -ErrorAction SilentlyContinue)) {
        return $false
    }

    $previousErrorActionPreference = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    try {
        & ssh `
            -i $keyPath `
            -o BatchMode=yes `
            -o ConnectTimeout=5 `
            -o StrictHostKeyChecking=accept-new `
            "ubuntu@$HostName" `
            "true" 2>&1 | Out-Null
        $exitCode = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $previousErrorActionPreference
    }

    return ($exitCode -eq 0)
}

function Invoke-MultipassExecWithRetry {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Arguments,
        [int]$TimeoutSeconds = 180,
        [int]$RetryDelaySeconds = 5
    )

    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    $lastMessage = $null
    $attempt = 0

    while ((Get-Date) -lt $deadline) {
        $attempt++
        $previousErrorActionPreference = $ErrorActionPreference
        $ErrorActionPreference = "Continue"
        try {
            $output = & $script:MultipassExe exec @Arguments 2>&1
            $exitCode = $LASTEXITCODE
        }
        finally {
            $ErrorActionPreference = $previousErrorActionPreference
        }

        if ($exitCode -eq 0) {
            return $output
        }

        $lastMessage = ($output | Out-String).Trim()
        Start-Sleep -Seconds $RetryDelaySeconds
    }

    if (-not $lastMessage) {
        $lastMessage = "Multipass exec nao respondeu dentro de $TimeoutSeconds segundos."
    }

    throw "Falha ao executar multipass exec apos $attempt tentativas: $lastMessage"
}

$script:MultipassExe = Get-MultipassExecutable

if (-not $VmIp) {
    $VmIp = Get-VmIp -Name $VmName -PreferredPrefixes $PreferredIpPrefixes
}

if (-not $VmIp) {
    $VmIp = "172.19.164.13"
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
if (-not $SkipKeyInjection) {
    # O teste previo com ssh.exe pode ficar bloqueado quando executado pelo
    # Agendador de Tarefas, mesmo em BatchMode. A injecao via Multipass e
    # idempotente e funciona antes mesmo de o SSH da VM estar acessivel.
    $remoteCommand = "set -e; mkdir -p ~/.ssh; chmod 700 ~/.ssh; printf '%s\n' '$publicKey' >> ~/.ssh/authorized_keys; sort -u ~/.ssh/authorized_keys -o ~/.ssh/authorized_keys; chmod 600 ~/.ssh/authorized_keys; (sudo systemctl enable --now ssh >/dev/null 2>&1 || systemctl enable --now ssh >/dev/null 2>&1 || true)"

    Invoke-MultipassExecWithRetry -Arguments @($VmName, '--', 'sh', '-lc', $remoteCommand) | Out-Null
}

function Add-SshConfigBlock {
    param(
        [string[]]$ExistingLines,
        [string]$BlockHeader,
        [string[]]$BlockLines
    )

    $outputLines = New-Object System.Collections.Generic.List[string]
    $currentBlock = New-Object System.Collections.Generic.List[string]
    $currentHeader = $null
    $targetHeaderPattern = "^[ \t]*Host\s+$([regex]::Escape($BlockHeader))[ \t]*$"

    foreach ($line in $ExistingLines) {
        if ($line -match '^[ \t]*(Host|Match)\b') {
            if ($currentBlock.Count -gt 0 -and -not ($currentHeader -and $currentHeader -match $targetHeaderPattern)) {
                foreach ($blockLine in $currentBlock) {
                    $outputLines.Add($blockLine)
                }
            }

            $currentBlock.Clear()
            $currentHeader = $line
        }

        $currentBlock.Add($line)
    }

    if ($currentBlock.Count -gt 0 -and -not ($currentHeader -and $currentHeader -match $targetHeaderPattern)) {
        foreach ($blockLine in $currentBlock) {
            $outputLines.Add($blockLine)
        }
    }

    if ($outputLines.Count -gt 0 -and $outputLines[$outputLines.Count - 1] -ne '') {
        $outputLines.Add('')
    }

    foreach ($line in $BlockLines) {
        $outputLines.Add($line)
    }

    return $outputLines.ToArray()
}

$existingConfigLines = @()
if (Test-Path -LiteralPath $configPath) {
    $existingConfigLines = Get-Content -LiteralPath $configPath
}

$sshBlock = @(
    "Host $VmName"
    "    HostName $VmIp"
    "    User ubuntu"
    "    Port 22"
    "    IdentityFile $keyPath"
    "    IdentitiesOnly yes"
    "    StrictHostKeyChecking accept-new"
)

$mergedConfig = Add-SshConfigBlock -ExistingLines $existingConfigLines -BlockHeader $VmName -BlockLines $sshBlock
try {
    $tempConfigPath = Join-Path $sshDir ("config.{0}.tmp" -f ([guid]::NewGuid().ToString("N")))
    Set-Content -Encoding ASCII -Force -Path $tempConfigPath -Value $mergedConfig
    Move-Item -Force -LiteralPath $tempConfigPath -Destination $configPath
}
catch {
    Write-Warning "Nao foi possivel atualizar o arquivo SSH config: $($_.Exception.Message)"
    if ($tempConfigPath -and (Test-Path -LiteralPath $tempConfigPath)) {
        Remove-Item -LiteralPath $tempConfigPath -Force -ErrorAction SilentlyContinue
    }
    throw
}

Write-Output "SSH config atualizado: $VmName -> $VmIp"
