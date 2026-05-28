$ErrorActionPreference = "Stop"

$vmName = "ia-lab"
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$snapshotName = "auto-$timestamp"
$logDir = "C:\IA-LAB\scripts\logs"
$logFile = Join-Path $logDir ("snapshot_multipass_{0:yyyyMMdd}.log" -f (Get-Date))

New-Item -ItemType Directory -Force -Path $logDir | Out-Null

function Write-Log {
    param([string]$Message)
    $line = "{0} {1}" -f (Get-Date -Format s), $Message
    Add-Content -Encoding UTF8 -Path $logFile -Value $line
    Write-Output $line
}

Write-Log "Criando snapshot $snapshotName da VM $vmName"
multipass snapshot $vmName --name $snapshotName
Write-Log "Snapshot criado: $snapshotName"

$snapshots = multipass info $vmName | Select-String "Snapshots:"
Write-Log ($snapshots -join " ")

$cleanupScript = Join-Path $PSScriptRoot "cleanup_multipass_snapshots.ps1"
if (Test-Path $cleanupScript) {
    & $cleanupScript -VmName $vmName -Keep 4 -Prefix "auto-"
}
