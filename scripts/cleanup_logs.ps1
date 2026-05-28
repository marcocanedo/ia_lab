param(
    [int]$RetentionDays = 30
)

$ErrorActionPreference = "Stop"

$paths = @(
    "C:\IA-LAB\scripts\logs",
    "C:\IA-LAB\backups\reports"
)

$cutoff = (Get-Date).AddDays(-$RetentionDays)

foreach ($path in $paths) {
    if (-not (Test-Path $path)) {
        continue
    }

    Get-ChildItem -Path $path -File -Recurse |
        Where-Object { $_.LastWriteTime -lt $cutoff } |
        ForEach-Object {
            Write-Output "Removendo $($_.FullName)"
            Remove-Item -LiteralPath $_.FullName -Force
        }
}
