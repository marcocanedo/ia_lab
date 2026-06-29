$ErrorActionPreference = "Stop"
. "$PSScriptRoot\_llamacpp_common.ps1"

$targets = @(
    [pscustomobject]@{ Port = 8001; Model = "qwen2.5-7b-instruct-gguf-q5_k_m" },
    [pscustomobject]@{ Port = 8002; Model = "qwen2.5-coder-7b-instruct-gguf-q5_k_m" },
    [pscustomobject]@{ Port = 8003; Model = "qwen2.5-14b-instruct-gguf-q4_k_m" }
)

foreach ($target in $targets) {
    Write-Host "Testando chat em 127.0.0.1:$($target.Port)..."
    $result = Invoke-LlamaChatTest -Port $target.Port -Model $target.Model
    $content = $result.choices[0].message.content
    Write-Host "Resposta $($target.Port): $content"
}
