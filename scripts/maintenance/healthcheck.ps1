$ErrorActionPreference = "Continue"

$vmName = "ia-lab"
$multipassExe = "C:\Program Files\Multipass\bin\multipass.exe"
$scriptsRoot = Split-Path -Parent $PSScriptRoot
$reportDir = Join-Path $scriptsRoot "logs\healthcheck"
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$jsonReport = Join-Path $reportDir "healthcheck_$timestamp.json"
$textReport = Join-Path $reportDir "healthcheck_$timestamp.txt"

New-Item -ItemType Directory -Force -Path $reportDir | Out-Null

function New-Check {
    param(
        [string]$Name,
        [string]$Status,
        [string]$Detail
    )

    [pscustomobject]@{
        name = $Name
        status = $Status
        detail = $Detail
        checked_at = (Get-Date).ToString("s")
    }
}

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

function Test-Port {
    param(
        [string]$Name,
        [string]$HostName,
        [int]$Port
    )

    try {
        $ok = Test-NetConnection $HostName -Port $Port -InformationLevel Quiet
        if ($ok) {
            return New-Check $Name "OK" "${HostName}:$Port reachable"
        }
        return New-Check $Name "FAIL" "${HostName}:$Port not reachable"
    }
    catch {
        return New-Check $Name "FAIL" $_.Exception.Message
    }
}

function Get-MultipassState {
    param(
        [string]$Name
    )

    $stateLine = & $script:MultipassExe list | Select-String ("^\s*{0}\s+" -f [regex]::Escape($Name)) | Select-Object -First 1
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
    param(
        [string]$Name
    )

    $info = & $script:MultipassExe info $Name 2>&1
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

function Test-VmExec {
    param(
        [string]$Name
    )

    $output = & $script:MultipassExe exec $Name -- true 2>&1
    if ($LASTEXITCODE -eq 0) {
        return New-Check "Multipass exec" "OK" "$Name respondeu"
    }

    return New-Check "Multipass exec" "FAIL" ($output | Out-String).Trim()
}

$script:MultipassExe = Get-MultipassExecutable
$checks = New-Object System.Collections.Generic.List[object]

$checks.Add((Test-Port "PX port" "127.0.0.1" 18080))

$pxProcesses = @(Get-Process -Name "px" -ErrorAction SilentlyContinue)
if ($pxProcesses.Count -eq 1) {
    $checks.Add((New-Check "PX process" "OK" "1 process detected"))
}
elseif ($pxProcesses.Count -gt 1) {
    $checks.Add((New-Check "PX process" "WARN" "$($pxProcesses.Count) processes detected"))
}
else {
    $checks.Add((New-Check "PX process" "FAIL" "No process detected"))
}

$multipassService = Get-Service -Name Multipass -ErrorAction SilentlyContinue
if ($multipassService -and $multipassService.Status -eq "Running") {
    $checks.Add((New-Check "Multipass service" "OK" "Running"))
}
elseif ($multipassService) {
    $checks.Add((New-Check "Multipass service" "FAIL" $multipassService.Status))
}
else {
    $checks.Add((New-Check "Multipass service" "FAIL" "Service not found"))
}

$vmState = Get-MultipassState -Name $vmName
if ($vmState -eq "Running") {
    $checks.Add((New-Check "VM state" "OK" "$vmName Running"))
    $checks.Add((Test-VmExec -Name $vmName))
}
elseif ($vmState) {
    $checks.Add((New-Check "VM state" "FAIL" "$vmName $vmState"))
}
else {
    $checks.Add((New-Check "VM state" "FAIL" "VM not found"))
}

$vmIp = Get-VmIp -Name $vmName
if ($vmIp) {
    $checks.Add((New-Check "VM IP" "OK" $vmIp))
    try {
        if (Test-NetConnection $vmIp -Port 22 -InformationLevel Quiet) {
            $checks.Add((New-Check "VM SSH" "OK" "$vmIp:22 reachable"))
        }
        else {
            $checks.Add((New-Check "VM SSH" "FAIL" "$vmIp:22 not reachable"))
        }
    }
    catch {
        $checks.Add((New-Check "VM SSH" "FAIL" $_.Exception.Message))
    }
}
else {
    $checks.Add((New-Check "VM IP" "FAIL" "Nao foi possivel detectar o IP da VM"))
}

$sshConfigPath = Join-Path $env:USERPROFILE ".ssh\config"
if ($vmIp -and (Test-Path -LiteralPath $sshConfigPath)) {
    $sshConfig = Get-Content -LiteralPath $sshConfigPath -Raw
    if ($sshConfig -match "(?ms)^\s*Host\s+$([regex]::Escape($vmName))\s+.*?^\s*HostName\s+$([regex]::Escape($vmIp))\s+") {
        $checks.Add((New-Check "SSH config" "OK" "$vmName aponta para $vmIp"))
    }
    else {
        $checks.Add((New-Check "SSH config" "FAIL" "Entrada $vmName fora de sincronia"))
    }
}
else {
    $checks.Add((New-Check "SSH config" "FAIL" "Arquivo de configuracao nao encontrado ou IP ausente"))
}

$summary = [pscustomobject]@{
    generated_at = (Get-Date).ToString("s")
    computer = $env:COMPUTERNAME
    checks = $checks
    status = if (($checks | Where-Object status -eq "FAIL").Count -gt 0) { "FAIL" } elseif (($checks | Where-Object status -eq "WARN").Count -gt 0) { "WARN" } else { "OK" }
}

$summary | ConvertTo-Json -Depth 6 | Set-Content -Encoding UTF8 $jsonReport

$lines = @()
$lines += "IA-LAB Base Healthcheck - $($summary.generated_at)"
$lines += "Status: $($summary.status)"
$lines += ""
foreach ($check in $checks) {
    $lines += "[$($check.status)] $($check.name) - $($check.detail)"
}
$lines | Set-Content -Encoding UTF8 $textReport

Write-Output ($lines -join "`n")
Write-Output ""
Write-Output "JSON: $jsonReport"
Write-Output "TXT:  $textReport"

if ($summary.status -eq "FAIL") {
    exit 1
}

exit 0
