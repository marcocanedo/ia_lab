param(
    [string]$VmName = "ia-lab",
    [int]$ProxyPort = 18080,
    [string]$ProxyHost,
    [switch]$Preview
)

$ErrorActionPreference = "Stop"

if (-not $ProxyHost) {
    $defaultRoute = multipass exec $VmName -- sh -lc "ip route show default | awk '{print `$3; exit}'"
    $ProxyHost = ($defaultRoute | Select-Object -First 1).Trim()
}

if (-not $ProxyHost) {
    throw "Nao foi possivel detectar o gateway da VM $VmName. Informe -ProxyHost manualmente."
}

$proxyUrl = "http://${ProxyHost}:$ProxyPort"
$localFile = Join-Path $PSScriptRoot "apt_95proxy"

if ($Preview) {
    Write-Host "Preview: nenhuma alteracao aplicada."
    Write-Host "  VM: $VmName"
    Write-Host "  Proxy apt: $proxyUrl"
    Write-Host "  Arquivo local: $localFile"
    exit 0
}

@(
    "Acquire::http::Proxy `"$proxyUrl`";"
    "Acquire::https::Proxy `"$proxyUrl`";"
) | Set-Content -Encoding ASCII $localFile

multipass transfer $localFile "${VmName}:/tmp/95proxy"
multipass exec $VmName -- sudo cp /tmp/95proxy /etc/apt/apt.conf.d/95proxy
multipass exec $VmName -- cat /etc/apt/apt.conf.d/95proxy

Write-Output "Proxy apt da VM configurado para $proxyUrl"
