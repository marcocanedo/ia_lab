$ErrorActionPreference = "Stop"

$hostValue = "0.0.0.0:11434"
$port = 11434
$proxyUrl = "http://127.0.0.1:18080"
$proxyPort = 18080
$noProxy = "localhost,127.0.0.1,::1"

Write-Host "Configurando variaveis Ollama..."

[Environment]::SetEnvironmentVariable("OLLAMA_HOST", $hostValue, "User")
[Environment]::SetEnvironmentVariable("HTTP_PROXY", $proxyUrl, "User")
[Environment]::SetEnvironmentVariable("HTTPS_PROXY", $proxyUrl, "User")
[Environment]::SetEnvironmentVariable("ALL_PROXY", $proxyUrl, "User")
[Environment]::SetEnvironmentVariable("NO_PROXY", $noProxy, "User")

$env:OLLAMA_HOST = $hostValue
$env:HTTP_PROXY = $proxyUrl
$env:HTTPS_PROXY = $proxyUrl
$env:ALL_PROXY = $proxyUrl
$env:NO_PROXY = $noProxy

$pxListening = Test-NetConnection 127.0.0.1 -Port $proxyPort -InformationLevel Quiet
if (-not $pxListening) {
    Write-Warning "PX nao esta escutando em 127.0.0.1:$proxyPort. Downloads do Ollama podem falhar em rede corporativa."
}

$ollama = Get-Command ollama -ErrorAction Stop

Write-Host "Iniciando Ollama..."

$alreadyListening = Test-NetConnection 127.0.0.1 -Port $port -InformationLevel Quiet
if (-not $alreadyListening) {
    Start-Process -WindowStyle Hidden $ollama.Source -ArgumentList "serve"
}
else {
    Write-Host "Ollama ja esta escutando na porta $port."
}

Write-Host "Aguardando Ollama na porta $port..."
for ($i = 1; $i -le 60; $i++) {
    $ready = Test-NetConnection 127.0.0.1 -Port $port -InformationLevel Quiet
    if ($ready) {
        Write-Host "Ollama pronto em 127.0.0.1:$port"
        return
    }
    Start-Sleep -Seconds 1
}

throw "Ollama nao abriu a porta $port"
