<#
.SYNOPSIS
  Inicia o PX e configura o Windows e ferramentas comuns para usar o proxy local.

.USAGE
  PowerShell como Administrador:
    powershell -ExecutionPolicy Bypass -File .\setup_px_proxy.ps1

  Para desfazer:
    powershell -ExecutionPolicy Bypass -File .\setup_px_proxy.ps1 -Disable

.NOTES
  Ajuste $PxPath, $Port e $ListenAddress se necessÃ¡rio.
#>

param(
    [switch]$Disable,
    [string]$PxPath = "D:\IA-LAB\px\px.exe",
    [int]$Port = 18080,
    [string]$ProxyHost = "127.0.0.1",
    [string]$ListenAddress = "127.0.0.1",
    [switch]$WslFriendly
)

$ErrorActionPreference = "Stop"

if ($WslFriendly) {
    # Permite que WSL/Docker acessem o proxy pela interface do Windows.
    # Use com cuidado em redes compartilhadas.
    $ListenAddress = "0.0.0.0"
}

$ProxyUrl = "http://$ProxyHost`:$Port"
$ProxyAddress = "$ProxyHost`:$Port"
$BypassList = "localhost;127.0.0.1;<local>"
$EnvNames = @("HTTP_PROXY", "HTTPS_PROXY", "ALL_PROXY", "http_proxy", "https_proxy", "all_proxy")
$NoProxyNames = @("NO_PROXY", "no_proxy")

function Write-Ok($msg) { Write-Host "[OK] $msg" -ForegroundColor Green }
function Write-Warn($msg) { Write-Host "[AVISO] $msg" -ForegroundColor Yellow }
function Write-Step($msg) { Write-Host "`n== $msg ==" -ForegroundColor Cyan }

function Refresh-InternetSettings {
    try {
        $signature = @"
using System;
using System.Runtime.InteropServices;
public class WinInetRefresh {
    [DllImport("wininet.dll", SetLastError = true)]
    public static extern bool InternetSetOption(IntPtr hInternet, int dwOption, IntPtr lpBuffer, int dwBufferLength);
}
"@
        Add-Type -TypeDefinition $signature -ErrorAction SilentlyContinue | Out-Null
        [WinInetRefresh]::InternetSetOption([IntPtr]::Zero, 39, [IntPtr]::Zero, 0) | Out-Null # INTERNET_OPTION_SETTINGS_CHANGED
        [WinInetRefresh]::InternetSetOption([IntPtr]::Zero, 37, [IntPtr]::Zero, 0) | Out-Null # INTERNET_OPTION_REFRESH
    }
    catch {
        Write-Warn "Nao consegui forcar refresh das configuracoes WinINET. Pode ser necessario reabrir aplicativos."
    }
}

function Start-PxProxy {
    Write-Step "Iniciando PX"

    if (-not (Test-Path $PxPath)) {
        throw "PX nao encontrado em: $PxPath"
    }

    $pxRunning = Get-Process px -ErrorAction SilentlyContinue | Where-Object {
        try { $_.Path -eq $PxPath } catch { $false }
    }

    if (-not $pxRunning) {
        Start-Process -WindowStyle Hidden -FilePath $PxPath -ArgumentList "--listen=$ListenAddress --port=$Port"
        Write-Ok "PX iniciado em $($ListenAddress):$Port"
    }
    else {
        Write-Ok "PX ja estava em execucao."
    }

    Write-Host "Aguardando porta $Port..."
    for ($i = 1; $i -le 30; $i++) {
        if (Test-NetConnection 127.0.0.1 -Port $Port -InformationLevel Quiet) {
            Write-Ok "PX respondendo em 127.0.0.1:$Port"
            return
        }
        Start-Sleep -Seconds 1
    }

    throw "PX nao abriu a porta $Port."
}

function Enable-Proxy {
    Start-PxProxy

    Write-Step "Configurando proxy do usuario Windows / WinINET"
    $internetSettings = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings"
    Set-ItemProperty -Path $internetSettings -Name ProxyEnable -Value 1
    Set-ItemProperty -Path $internetSettings -Name ProxyServer -Value $ProxyAddress
    Set-ItemProperty -Path $internetSettings -Name ProxyOverride -Value $BypassList
    Refresh-InternetSettings
    Write-Ok "WinINET configurado: $ProxyAddress"

    Write-Step "Configurando WinHTTP"
    try {
        netsh winhttp set proxy proxy-server="$ProxyAddress" bypass-list="$BypassList" | Out-Host
        Write-Ok "WinHTTP configurado."
    }
    catch {
        Write-Warn "Falha ao configurar WinHTTP. Rode o PowerShell como Administrador."
    }

    Write-Step "Configurando variaveis de ambiente do usuario"
    foreach ($name in $EnvNames) {
        [Environment]::SetEnvironmentVariable($name, $ProxyUrl, "User")
        Set-Item -Path "Env:$name" -Value $ProxyUrl
    }
    foreach ($name in $NoProxyNames) {
        [Environment]::SetEnvironmentVariable($name, "localhost,127.0.0.1,.local", "User")
        Set-Item -Path "Env:$name" -Value "localhost,127.0.0.1,.local"
    }
    Write-Ok "Variaveis HTTP_PROXY/HTTPS_PROXY/ALL_PROXY configuradas."

    Write-Step "Configurando ferramentas comuns, se existirem"

    if (Get-Command git -ErrorAction SilentlyContinue) {
        git config --global http.proxy $ProxyUrl
        git config --global https.proxy $ProxyUrl
        Write-Ok "Git configurado."
    }
    else { Write-Warn "Git nao encontrado no PATH." }

    if (Get-Command npm -ErrorAction SilentlyContinue) {
        npm config set proxy $ProxyUrl | Out-Null
        npm config set https-proxy $ProxyUrl | Out-Null
        Write-Ok "npm configurado."
    }
    else { Write-Warn "npm nao encontrado no PATH." }

    if (Get-Command pip -ErrorAction SilentlyContinue) {
        pip config set global.proxy $ProxyUrl | Out-Null
        Write-Ok "pip configurado."
    }
    else { Write-Warn "pip nao encontrado no PATH." }

    if (Get-Command conda -ErrorAction SilentlyContinue) {
        conda config --set proxy_servers.http $ProxyUrl | Out-Null
        conda config --set proxy_servers.https $ProxyUrl | Out-Null
        Write-Ok "conda configurado."
    }
    else { Write-Warn "conda nao encontrado no PATH." }

    Write-Step "Teste rapido"
    Write-Host "Processo PX:"
    Get-Process px -ErrorAction SilentlyContinue | Select-Object Id, ProcessName, Path | Format-Table -AutoSize

    Write-Host "`nPorta local:"
    Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue | Select-Object LocalAddress, LocalPort, State, OwningProcess | Format-Table -AutoSize

    Write-Host "`nConfig WinHTTP:"
    netsh winhttp show proxy | Out-Host

    Write-Ok "Configuracao concluida. Reabra terminals/apps para herdarem as variaveis novas."
}

function Disable-Proxy {
    Write-Step "Desativando proxy do usuario Windows / WinINET"
    $internetSettings = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings"
    Set-ItemProperty -Path $internetSettings -Name ProxyEnable -Value 0
    Refresh-InternetSettings
    Write-Ok "WinINET desativado."

    Write-Step "Resetando WinHTTP"
    try {
        netsh winhttp reset proxy | Out-Host
        Write-Ok "WinHTTP resetado."
    }
    catch {
        Write-Warn "Falha ao resetar WinHTTP. Rode o PowerShell como Administrador."
    }

    Write-Step "Removendo variaveis de ambiente do usuario"
    foreach ($name in ($EnvNames + $NoProxyNames)) {
        [Environment]::SetEnvironmentVariable($name, $null, "User")
        Remove-Item -Path "Env:$name" -ErrorAction SilentlyContinue
    }
    Write-Ok "Variaveis removidas."

    Write-Step "Removendo configuracoes de ferramentas, se existirem"
    if (Get-Command git -ErrorAction SilentlyContinue) {
        git config --global --unset http.proxy 2>$null
        git config --global --unset https.proxy 2>$null
        Write-Ok "Git limpo."
    }
    if (Get-Command npm -ErrorAction SilentlyContinue) {
        npm config delete proxy | Out-Null
        npm config delete https-proxy | Out-Null
        Write-Ok "npm limpo."
    }
    if (Get-Command pip -ErrorAction SilentlyContinue) {
        pip config unset global.proxy 2>$null
        Write-Ok "pip limpo."
    }
    if (Get-Command conda -ErrorAction SilentlyContinue) {
        conda config --remove-key proxy_servers 2>$null
        Write-Ok "conda limpo."
    }

    Write-Ok "Proxy desativado. Reabra terminals/apps para limpar ambiente herdado."
}

if ($Disable) {
    Disable-Proxy
}
else {
    Enable-Proxy
}

