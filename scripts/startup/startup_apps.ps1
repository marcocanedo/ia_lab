$ErrorActionPreference = "Stop"

$startupRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$scriptsRoot = Split-Path -Parent $startupRoot
$logDir = Join-Path $scriptsRoot "logs"
$logFile = Join-Path $logDir ("startup_apps_{0:yyyyMMdd_HHmmss}.log" -f (Get-Date))

New-Item -ItemType Directory -Path $logDir -Force | Out-Null
Start-Transcript -Path $logFile -Append | Out-Null

try {
    Write-Host "IA-LAB startup de logon iniciado em $(Get-Date -Format s)"

    $pxScript = Join-Path $startupRoot "startup_px.ps1"
    $vmScript = Join-Path $startupRoot "startup_vm.ps1"
    $windowsProxyScript = Join-Path $startupRoot "sync_windows_proxy.ps1"

    foreach ($path in @($pxScript, $windowsProxyScript, $vmScript)) {
        if (-not (Test-Path -LiteralPath $path)) {
            throw "Script nao encontrado: $path"
        }
    }

    Write-Host "Executando startup_px.ps1..."
    try {
        & $pxScript
        Write-Host "startup_px.ps1 concluido."
    }
    catch {
        Write-Warning "startup_px.ps1 falhou: $($_.Exception.Message)"
    }

    Write-Host "Sincronizando proxy dos aplicativos Windows..."
    try {
        & $windowsProxyScript
        Write-Host "Proxy dos aplicativos Windows sincronizado."
    }
    catch {
        Write-Warning "Sincronizacao do proxy Windows falhou: $($_.Exception.Message)"
    }

    Write-Host "Executando startup_vm.ps1 em modo completo no contexto do usuario..."
    try {
        & $vmScript
        Write-Host "startup_vm.ps1 concluido."
    }
    catch {
        Write-Warning "startup_vm.ps1 falhou: $($_.Exception.Message)"
    }

    Write-Host "IA-LAB startup de logon concluido em $(Get-Date -Format s)"
}
finally {
    Stop-Transcript | Out-Null
}

