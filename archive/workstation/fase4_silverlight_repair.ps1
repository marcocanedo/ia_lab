$ErrorActionPreference = 'Continue'

Start-Transcript -Path 'C:\IA-LAB\silverlight_repair_then_uninstall.log' -Force

$productCode = '{89F4137D-6C26-4A84-BDB8-2E5A4BB71E00}'

$repair = Start-Process -FilePath 'msiexec.exe' -ArgumentList @(
    '/fa',
    $productCode,
    '/norestart',
    '/L*v',
    'C:\IA-LAB\silverlight_repair.log'
) -Wait -PassThru
Write-Host "RepairExit=$($repair.ExitCode)"

$uninstall = Start-Process -FilePath 'msiexec.exe' -ArgumentList @(
    '/X',
    $productCode,
    '/norestart',
    '/L*v',
    'C:\IA-LAB\silverlight_uninstall_after_repair.log'
) -Wait -PassThru
Write-Host "UninstallExit=$($uninstall.ExitCode)"

foreach ($path in @('C:\Program Files\MicroStrategy', 'C:\Program Files (x86)\RSUPPORT')) {
    if (Test-Path -LiteralPath $path) {
        $children = Get-ChildItem -LiteralPath $path -Force -ErrorAction SilentlyContinue
        if (-not $children) {
            Write-Host "Removing empty directory: $path"
            Remove-Item -LiteralPath $path -Force -ErrorAction Continue
        } else {
            Write-Host "Directory not empty, keeping: $path"
        }
    }
}

Stop-Transcript
