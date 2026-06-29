param(
    [string]$VmName = "ia-lab",
    [int]$Keep = 4,
    [string]$Prefix = "auto-"
)

$ErrorActionPreference = "Stop"

$logDir = "C:\IA-LAB\scripts\logs"
$logFile = Join-Path $logDir ("cleanup_multipass_snapshots_{0:yyyyMMdd}.log" -f (Get-Date))

New-Item -ItemType Directory -Force -Path $logDir | Out-Null

function Write-Log {
    param([string]$Message)
    $line = "{0} {1}" -f (Get-Date -Format s), $Message
    Add-Content -Encoding UTF8 -Path $logFile -Value $line
    Write-Output $line
}

$raw = multipass info $VmName
$snapshotLines = $raw | Where-Object { $_ -match "^\s+$Prefix" }
$snapshots = @()

foreach ($line in $snapshotLines) {
    $name = ($line.Trim() -split "\s+")[0]
    if ($name -like "$Prefix*") {
        $snapshots += $name
    }
}

$snapshots = $snapshots | Sort-Object -Descending

if ($snapshots.Count -le $Keep) {
    Write-Log "Retencao OK: $($snapshots.Count) snapshot(s), keep=$Keep"
    exit 0
}

$toDelete = $snapshots | Select-Object -Skip $Keep
foreach ($snapshot in $toDelete) {
    Write-Log "Removendo snapshot antigo: $snapshot"
    multipass delete "$VmName.$snapshot"
    multipass purge
}

Write-Log "Cleanup concluido. Mantidos $Keep snapshot(s) auto-*."
