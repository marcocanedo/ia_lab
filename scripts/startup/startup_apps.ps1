$ErrorActionPreference = "Stop"

$startupRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$scriptsRoot = Split-Path -Parent $startupRoot
$logDir = Join-Path $scriptsRoot "logs"
$logFile = Join-Path $logDir ("startup_apps_{0:yyyyMMdd_HHmmss}.log" -f (Get-Date))

New-Item -ItemType Directory -Path $logDir -Force | Out-Null
Start-Transcript -Path $logFile -Append | Out-Null

try {
    Write-Host "IA-LAB startup base iniciado em $(Get-Date -Format s)"

    $steps = @("startup_px.ps1", "startup_vm.ps1")

    foreach ($step in $steps) {
        $path = Join-Path $startupRoot $step
        if (-not (Test-Path -LiteralPath $path)) {
            throw "Script nao encontrado: $path"
        }

        Write-Host "Executando $step..."
        & $path
        Write-Host "$step concluido."
    }

    Write-Host "IA-LAB startup base concluido em $(Get-Date -Format s)"
}
finally {
    Stop-Transcript | Out-Null
}

