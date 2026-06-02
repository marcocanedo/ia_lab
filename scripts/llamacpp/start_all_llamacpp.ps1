param(
    [switch]$Include14B
)

$ErrorActionPreference = "Stop"
& "$PSScriptRoot\start_qwen25_7b.ps1"
& "$PSScriptRoot\start_qwen25_coder_7b.ps1"
if ($Include14B) {
    & "$PSScriptRoot\start_qwen25_14b.ps1"
}
else {
    Write-Host "14B nao iniciado por padrao. Use -Include14B quando quiser iniciar tambem a porta 8003."
}
