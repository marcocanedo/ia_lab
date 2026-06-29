$ErrorActionPreference = "Continue"
. "$PSScriptRoot\_llamacpp_common.ps1"
Initialize-LlamaCppPaths

$checks = New-Object System.Collections.Generic.List[object]

function Add-Check {
    param([string]$Name, [string]$Status, [string]$Detail)
    $checks.Add([pscustomobject]@{
        name = $Name
        status = $Status
        detail = $Detail
        checked_at = (Get-Date).ToString("s")
    })
}

$modelDefs = @(
    [pscustomobject]@{ Name = "Qwen2.5 7B"; Port = 8001; Dir = "qwen2.5-7b-instruct-q5_k_m"; Pattern = "qwen2.5-7b-instruct-q5_k_m*.gguf"; Model = "qwen2.5-7b-instruct-gguf-q5_k_m" },
    [pscustomobject]@{ Name = "Qwen2.5 Coder 7B"; Port = 8002; Dir = "qwen2.5-coder-7b-instruct-q5_k_m"; Pattern = "qwen2.5-coder-7b-instruct-q5_k_m-*.gguf"; Model = "qwen2.5-coder-7b-instruct-gguf-q5_k_m" },
    [pscustomobject]@{ Name = "Qwen2.5 14B"; Port = 8003; Dir = "qwen2.5-14b-instruct-q4_k_m"; Pattern = "qwen2.5-14b-instruct-q4_k_m*.gguf"; Model = "qwen2.5-14b-instruct-gguf-q4_k_m" }
)

try {
    $server = Get-LlamaServerPath
    Add-Check "llama-server.exe" "OK" $server
}
catch {
    Add-Check "llama-server.exe" "FAIL" $_.Exception.Message
}

foreach ($model in $modelDefs) {
    try {
        $files = @(Get-GgufFiles -ModelDirectory $model.Dir -Pattern $model.Pattern)
        Add-Check "$($model.Name) GGUF" "OK" "$($files.Count) arquivo(s)"
    }
    catch {
        Add-Check "$($model.Name) GGUF" "FAIL" $_.Exception.Message
    }

    $portOk = Test-NetConnection 127.0.0.1 -Port $model.Port -InformationLevel Quiet
    $portStatus = if ($portOk) { "OK" } else { "WARN" }
    $portDetail = if ($portOk) { "127.0.0.1:$($model.Port) reachable" } else { "servidor nao esta em execucao" }
    Add-Check "$($model.Name) porta $($model.Port)" $portStatus $portDetail

    if ($portOk) {
        try {
            $models = Invoke-RestMethod -Uri "http://127.0.0.1:$($model.Port)/v1/models" -TimeoutSec 15
            Add-Check "$($model.Name) /v1/models" "OK" "$(@($models.data).Count) modelo(s)"
        }
        catch {
            Add-Check "$($model.Name) /v1/models" "FAIL" $_.Exception.Message
        }
    }
}

$processes = @(Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.ProcessName -match "^llama" })
$procStatus = if ($processes.Count -gt 0) { "OK" } else { "WARN" }
Add-Check "Processos llama" $procStatus "$($processes.Count) processo(s)"

$drive = Get-PSDrive -Name C
$diskStatus = if ($drive.Free -gt 20GB) { "OK" } else { "WARN" }
Add-Check "Espaco em disco C" $diskStatus ("{0:N1} GB livres" -f ($drive.Free / 1GB))

$failCount = @($checks | Where-Object { $_.status -eq "FAIL" }).Count
$warnCount = @($checks | Where-Object { $_.status -eq "WARN" }).Count
$status = if ($failCount -gt 0) { "FAIL" } elseif ($warnCount -gt 0) { "WARN" } else { "OK" }
$report = [pscustomobject]@{
    generated_at = (Get-Date).ToString("s")
    status = $status
    checks = $checks
}

$json = Join-Path $script:LogRoot ("healthcheck_llamacpp_{0:yyyyMMdd_HHmmss}.json" -f (Get-Date))
$txt = Join-Path $script:LogRoot ("healthcheck_llamacpp_{0:yyyyMMdd_HHmmss}.txt" -f (Get-Date))
$report | ConvertTo-Json -Depth 6 | Set-Content -Encoding UTF8 -LiteralPath $json

$lines = @("IA-LAB llama.cpp Healthcheck - $($report.generated_at)", "Status: $status", "")
foreach ($check in $checks) {
    $lines += "[$($check.status)] $($check.name) - $($check.detail)"
}
$lines | Set-Content -Encoding UTF8 -LiteralPath $txt
$lines -join "`n"
Write-Host ""
Write-Host "JSON: $json"
Write-Host "TXT:  $txt"

if ($status -eq "FAIL") { exit 1 }
exit 0
