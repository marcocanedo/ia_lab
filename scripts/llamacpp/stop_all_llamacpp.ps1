$ErrorActionPreference = "Continue"
. "$PSScriptRoot\_llamacpp_common.ps1"
Initialize-LlamaCppPaths

$pidFiles = @(Get-ChildItem -LiteralPath $script:PidRoot -Filter "*.pid" -File -ErrorAction SilentlyContinue)
foreach ($pidFile in $pidFiles) {
    $pidValue = (Get-Content -LiteralPath $pidFile.FullName -Raw).Trim()
    if ($pidValue -match '^\d+$') {
        $process = Get-Process -Id ([int]$pidValue) -ErrorAction SilentlyContinue
        if ($process -and $process.ProcessName -match "llama") {
            Write-Host "Parando $($process.ProcessName) PID $pidValue..."
            Stop-Process -Id ([int]$pidValue) -Force
        }
    }
    Remove-Item -LiteralPath $pidFile.FullName -Force -ErrorAction SilentlyContinue
}

Write-Host "Processos llama-server controlados pelos PID files foram encerrados."
