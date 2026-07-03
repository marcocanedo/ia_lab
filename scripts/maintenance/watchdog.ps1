$ErrorActionPreference = "Continue"

$scriptsRoot = Split-Path -Parent $PSScriptRoot
$startupRoot = Join-Path $scriptsRoot "startup"
$logDir = Join-Path $scriptsRoot "logs"
$logFile = Join-Path $logDir ("watchdog_{0:yyyyMMdd}.log" -f (Get-Date))

New-Item -ItemType Directory -Force -Path $logDir | Out-Null

function Write-Log {
    param([string]$Message)
    $line = "{0} {1}" -f (Get-Date -Format s), $Message
    Add-Content -Encoding UTF8 -Path $logFile -Value $line
    Write-Output $line
}

function Test-PortQuiet {
    param([int]$Port)
    return Test-NetConnection 127.0.0.1 -Port $Port -InformationLevel Quiet
}

function Get-MultipassExecutable {
    $candidate = "C:\Program Files\Multipass\bin\multipass.exe"
    if (Test-Path -LiteralPath $candidate) {
        return $candidate
    }

    $command = Get-Command multipass -ErrorAction SilentlyContinue
    if ($command) {
        return $command.Source
    }

    return $null
}

function Get-VmState {
    param([string]$Name)

    $multipassExe = Get-MultipassExecutable
    if (-not $multipassExe) {
        return $null
    }

    $stateLine = & $multipassExe list | Select-String ("^\s*{0}\s+" -f [regex]::Escape($Name)) | Select-Object -First 1
    if (-not $stateLine) {
        return $null
    }

    $tokens = $stateLine.ToString().Trim() -split "\s+"
    if ($tokens.Count -lt 2) {
        return $null
    }

    return $tokens[1]
}

function Get-VmIp {
    param([string]$Name)

    $multipassExe = Get-MultipassExecutable
    if (-not $multipassExe) {
        return $null
    }

    $info = & $multipassExe info $Name 2>&1
    if ($LASTEXITCODE -ne 0) {
        return $null
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

Write-Log "Watchdog base iniciado"

if (-not (Test-PortQuiet 18080)) {
    Write-Log "PX indisponivel; executando startup_px.ps1"
    & (Join-Path $startupRoot "startup_px.ps1")
}

$vmName = "ia-lab"
$vmState = Get-VmState -Name $vmName
$vmIp = if ($vmState -eq "Running") { Get-VmIp -Name $vmName } else { $null }
$vmReady = $false

if ($vmState -eq "Running" -and $vmIp) {
    try {
        $vmReady = Test-NetConnection $vmIp -Port 22 -InformationLevel Quiet
    }
    catch {
        $vmReady = $false
    }
}

if (-not $vmReady) {
    Write-Log "VM $vmName indisponivel; executando startup_vm.ps1"
    try {
        & (Join-Path $startupRoot "startup_vm.ps1")
    }
    catch {
        Write-Log "Falha ao iniciar a VM base: $($_.Exception.Message)"
    }
}
else {
    Write-Log "VM $vmName OK"
}

Write-Log "Watchdog concluido"
