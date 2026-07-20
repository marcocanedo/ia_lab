param(
    [int]$Port = 18080
)

$ErrorActionPreference = "Stop"

$proxyAddress = "127.0.0.1:$Port"
$proxyUrl = "http://$proxyAddress"
$internetSettings = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings"

# A politica corporativa mantem uma lista extensa de destinos internos que nao
# devem passar pelo proxy. Preserve-a e acrescente apenas as excecoes locais.
$existingBypass = [string](Get-ItemPropertyValue -Path $internetSettings -Name ProxyOverride -ErrorAction SilentlyContinue)
$bypassEntries = @($existingBypass -split ";" | ForEach-Object { $_.Trim() } | Where-Object { $_ })
$bypassEntries += @("localhost", "127.0.0.1", "<local>")
$bypassEntries = @($bypassEntries | Select-Object -Unique)
$bypassWinInet = $bypassEntries -join ";"

$environmentBypassEntries = @($bypassEntries | Where-Object { $_ -ne "<local>" })
$environmentBypassEntries += @("::1", ".local")
$bypassEnvironment = (@($environmentBypassEntries | Select-Object -Unique)) -join ","

Set-ItemProperty -Path $internetSettings -Name ProxyEnable -Value 1
Set-ItemProperty -Path $internetSettings -Name ProxyServer -Value $proxyAddress
Set-ItemProperty -Path $internetSettings -Name ProxyOverride -Value $bypassWinInet

foreach ($name in @("HTTP_PROXY", "HTTPS_PROXY", "ALL_PROXY", "http_proxy", "https_proxy", "all_proxy")) {
    [Environment]::SetEnvironmentVariable($name, $proxyUrl, "User")
    Set-Item -Path "Env:$name" -Value $proxyUrl
}

foreach ($name in @("NO_PROXY", "no_proxy")) {
    [Environment]::SetEnvironmentVariable($name, $bypassEnvironment, "User")
    Set-Item -Path "Env:$name" -Value $bypassEnvironment
}

try {
    $signature = @"
using System;
using System.Runtime.InteropServices;
public static class IaLabWinInetRefresh {
    [DllImport("wininet.dll", SetLastError = true)]
    public static extern bool InternetSetOption(IntPtr hInternet, int option, IntPtr buffer, int bufferLength);
}
"@
    Add-Type -TypeDefinition $signature -ErrorAction SilentlyContinue | Out-Null
    [IaLabWinInetRefresh]::InternetSetOption([IntPtr]::Zero, 39, [IntPtr]::Zero, 0) | Out-Null
    [IaLabWinInetRefresh]::InternetSetOption([IntPtr]::Zero, 37, [IntPtr]::Zero, 0) | Out-Null
}
catch {
    Write-Warning "Nao foi possivel notificar o WinINET imediatamente: $($_.Exception.Message)"
}

Write-Host "Proxy do Windows sincronizado com $proxyUrl"
