param(
    [string[]]$MonitoredProcesses = @("px", "ollama")
)

$ErrorActionPreference = "Continue"

$root = "C:\IA-LAB"
$reportDir = Join-Path $root "backups\reports"
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

function Invoke-CommandText {
    param([string]$Command)

    try {
        $output = powershell.exe -NoProfile -NonInteractive -WindowStyle Hidden -Command $Command 2>&1
        return @{
            exit_code = $LASTEXITCODE
            output = ($output -join "`n")
        }
    }
    catch {
        return @{
            exit_code = 1
            output = $_.Exception.Message
        }
    }
}

function Add-ProcessCheck {
    param(
        [System.Collections.Generic.List[object]]$CheckList,
        [string]$Name,
        [int]$MinCount = 1,
        [int]$MaxCount = 1
    )

    $processes = @(Get-Process -Name $Name -ErrorAction SilentlyContinue)
    $count = $processes.Count

    if ($count -lt $MinCount) {
        $CheckList.Add((New-Check "$Name process" "FAIL" "No process detected"))
        return
    }

    if ($count -gt $MaxCount) {
        $CheckList.Add((New-Check "$Name process" "WARN" "$count processes detected"))
        return
    }

    $CheckList.Add((New-Check "$Name process" "OK" "$count process(es) detected"))
}

$checks = New-Object System.Collections.Generic.List[object]

$checks.Add((Test-Port "PX port" "127.0.0.1" 18080))
$checks.Add((Test-Port "Ollama GPU port" "127.0.0.1" 11434))
$checks.Add((Test-Port "Ollama CPU port" "127.0.0.1" 11435))
$checks.Add((Test-Port "Ollama router port" "127.0.0.1" 11436))
$checks.Add((Test-Port "Open WebUI portproxy" "127.0.0.1" 3000))

try {
    $ollamaTags = Invoke-RestMethod -Uri "http://127.0.0.1:11436/api/tags" -TimeoutSec 10
    $modelCount = @($ollamaTags.models).Count
    $checks.Add((New-Check "Ollama API" "OK" "$modelCount models available"))
}
catch {
    $checks.Add((New-Check "Ollama API" "FAIL" $_.Exception.Message))
}

try {
    $webuiConfig = Invoke-RestMethod -Uri "http://127.0.0.1:3000/api/config" -TimeoutSec 10
    $checks.Add((New-Check "Open WebUI API" "OK" "version $($webuiConfig.version)"))
}
catch {
    $checks.Add((New-Check "Open WebUI API" "FAIL" $_.Exception.Message))
}

$multipass = Invoke-CommandText "multipass info ia-lab"
if ($multipass.exit_code -eq 0 -and $multipass.output -match "State:\s+Running") {
    $checks.Add((New-Check "Multipass VM ia-lab" "OK" "VM running"))
}
else {
    $checks.Add((New-Check "Multipass VM ia-lab" "FAIL" $multipass.output))
}

$docker = Invoke-CommandText "multipass exec ia-lab -- docker inspect -f '{{.State.Health.Status}} {{.State.Status}}' open-webui"
if ($docker.exit_code -eq 0 -and $docker.output -match "healthy\s+running") {
    $checks.Add((New-Check "Docker Open WebUI" "OK" $docker.output.Trim()))
}
else {
    $checks.Add((New-Check "Docker Open WebUI" "FAIL" $docker.output))
}

$portproxy = Invoke-CommandText "netsh interface portproxy show all"
if ($portproxy.output -match "127\.0\.0\.1\s+3000\s+\d+\.\d+\.\d+\.\d+\s+3000") {
    $checks.Add((New-Check "Windows portproxy" "OK" "127.0.0.1:3000 mapped to VM:3000"))
}
else {
    $checks.Add((New-Check "Windows portproxy" "FAIL" $portproxy.output))
}

foreach ($processName in $MonitoredProcesses) {
    if ([string]::IsNullOrWhiteSpace($processName)) {
        continue
    }

    $normalizedName = $processName.Trim()
    $maxCount = if ($normalizedName -ieq "ollama") { 2 } else { 1 }
    Add-ProcessCheck -CheckList $checks -Name $normalizedName -MaxCount $maxCount
}

$summary = [pscustomobject]@{
    generated_at = (Get-Date).ToString("s")
    computer = $env:COMPUTERNAME
    checks = $checks
    status = if (($checks | Where-Object status -eq "FAIL").Count -gt 0) { "FAIL" } elseif (($checks | Where-Object status -eq "WARN").Count -gt 0) { "WARN" } else { "OK" }
}

$summary | ConvertTo-Json -Depth 6 | Set-Content -Encoding UTF8 $jsonReport

$lines = @()
$lines += "IA-LAB Healthcheck - $($summary.generated_at)"
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
