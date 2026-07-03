param(
    [int]$Port = 18080,
    [string]$ProxyHost = "127.0.0.1",
    [string]$TestUrl = "https://www.microsoft.com"
)

$ProxyUrl = "http://$ProxyHost`:$Port"
Write-Host "== Verificando PX / Proxy ==" -ForegroundColor Cyan

Write-Host "`nProcesso px.exe:"
Get-Process px -ErrorAction SilentlyContinue | Select-Object Id, ProcessName, Path | Format-Table -AutoSize

Write-Host "`nPorta $Port escutando:"
$tcp = Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue
if ($tcp) {
    $tcp | Select-Object LocalAddress, LocalPort, State, OwningProcess | Format-Table -AutoSize
} else {
    Write-Host "Nada escutando na porta $Port" -ForegroundColor Red
}

Write-Host "`nTest-NetConnection 127.0.0.1:$($Port):"
Test-NetConnection 127.0.0.1 -Port $Port -InformationLevel Detailed

Write-Host "`nProxy WinINET do usuario:"
$internetSettings = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings"
Get-ItemProperty -Path $internetSettings | Select-Object ProxyEnable, ProxyServer, ProxyOverride | Format-List

Write-Host "`nProxy WinHTTP:"
netsh winhttp show proxy

Write-Host "`nVariaveis de ambiente da sessao atual:"
Get-ChildItem Env: | Where-Object { $_.Name -match '^(HTTP|HTTPS|ALL|NO)_PROXY$|^(http|https|all|no)_proxy$' } | Sort-Object Name | Format-Table -AutoSize

Write-Host "`nTeste de navegacao via proxy: $TestUrl"
try {
    $r = Invoke-WebRequest -Uri $TestUrl -Proxy $ProxyUrl -UseBasicParsing -TimeoutSec 20
    Write-Host "OK: HTTP $($r.StatusCode) usando $ProxyUrl" -ForegroundColor Green
}
catch {
    Write-Host "FALHOU usando $ProxyUrl" -ForegroundColor Red
    Write-Host $_.Exception.Message
}
