$ErrorActionPreference = "Stop"

$proxyUrl = "http://172.19.224.1:18080"
$localFile = Join-Path $PSScriptRoot "apt_95proxy"

if (-not (Test-Path $localFile)) {
    @(
        "Acquire::http::Proxy `"$proxyUrl`";"
        "Acquire::https::Proxy `"$proxyUrl`";"
    ) | Set-Content -Encoding ASCII $localFile
}

multipass transfer $localFile ia-lab:/tmp/95proxy
multipass exec ia-lab -- sudo cp /tmp/95proxy /etc/apt/apt.conf.d/95proxy
multipass exec ia-lab -- cat /etc/apt/apt.conf.d/95proxy

Write-Output "Proxy apt da VM configurado para $proxyUrl"
