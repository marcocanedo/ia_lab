# testar-modelos-litellm.ps1
# Testa modelos LiteLLM via endpoint OpenAI-compatible usando curl.exe no Windows
# Autor: Marco + Crystal

$ErrorActionPreference = "Continue"

# ==============================
# CONFIGURAÇÃO
# ==============================

$baseUrl = "https://reprllm.online/v1/chat/completions"

# Deixe vazio para não usar proxy manual.
# Se precisar usar seu proxy local/PX, troque para:
# $proxyUrl = "http://127.0.0.1:18080"
$proxyUrl = ""

# Tempo máximo por modelo, em segundos
$timeoutSeconds = 120

# Pausa entre testes, em segundos
$pauseSeconds = 2

# ==============================
# VALIDAÇÕES INICIAIS
# ==============================

if ([string]::IsNullOrWhiteSpace($env:REPRLLM_API_KEY)) {
    Write-Host "ERRO: variável REPRLLM_API_KEY não está definida." -ForegroundColor Red
    Write-Host ""
    Write-Host "Defina temporariamente nesta sessão com:" -ForegroundColor Yellow
    Write-Host '$env:REPRLLM_API_KEY = "SUA_CHAVE_LITELLM"' -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Ou defina de forma permanente com:" -ForegroundColor Yellow
    Write-Host '[Environment]::SetEnvironmentVariable("REPRLLM_API_KEY", "SUA_CHAVE_LITELLM", "User")' -ForegroundColor Yellow
    exit 1
}

$curlCmd = Get-Command curl.exe -ErrorAction SilentlyContinue

if (-not $curlCmd) {
    Write-Host "ERRO: curl.exe não encontrado no Windows." -ForegroundColor Red
    Write-Host "Teste no PowerShell: curl.exe --version"
    exit 1
}

Write-Host "Usando curl.exe em: $($curlCmd.Source)" -ForegroundColor Cyan
Write-Host "Endpoint: $baseUrl" -ForegroundColor Cyan

if (-not [string]::IsNullOrWhiteSpace($proxyUrl)) {
    Write-Host "Proxy manual ativado: $proxyUrl" -ForegroundColor Yellow
}
else {
    Write-Host "Proxy manual: desativado" -ForegroundColor DarkGray
}

# ==============================
# LISTA DE MODELOS
# ==============================

$models = @(
    # Agrupador retornado por /v1/models
    "all-team-models",

    # Claude
    "claude-fable-5",
    "claude-haiku-4-5",
    "claude-opus-4",
    "claude-opus-4-1",
    "claude-opus-4-5",
    "claude-opus-4-6",
    "claude-opus-4-7",
    "claude-opus-4-8-high",
    "claude-opus-4-8-low",
    "claude-opus-4-8-max",
    "claude-opus-4-8-medium",
    "claude-opus-4-8-xhigh",
    "claude-sonnet-4",
    "claude-sonnet-4-5",
    "claude-sonnet-4-6",

    # DeepSeek
    "deepseek-ocr-maas",
    "deepseek-v3.2-maas",

    # Gemini
    "gemini-2.5-flash",
    "gemini-2.5-flash-lite",
    "gemini-2.5-flash-lite-preview-09-2025",
    "gemini-2.5-flash-preview-09-2025",
    "gemini-2.5-pro",
    "gemini-3.1-flash-lite",
    "gemini-3.1-pro-preview",
    "gemini-3.5-flash",
    "gemini-live-2.5-flash",

    # Gemma / GLM
    "gemma-4-26b-a4b-it-maas",
    "glm-4.7-maas",
    "glm-5-maas",

    # GPT OSS
    "gpt-oss-120b-maas",
    "gpt-oss-20b-maas",

    # Kimi
    "kimi-k2-thinking-maas",

    # Llama
    "llama-3.3-70b-instruct-maas",
    "llama-4-maverick-17b-128e-instruct-maas",
    "llama-4-scout-17b-16e-instruct-maas",

    # MiniMax
    "minimax-m2-maas",

    # Qwen
    "qwen3-235b-a22b-instruct-2507-maas",
    "qwen3-coder-480b-a35b-instruct-maas",
    "qwen3-next-80b-a3b-instruct-maas",
    "qwen3-next-80b-a3b-thinking-maas"
)

# ==============================
# FUNÇÕES
# ==============================

function Get-ShortErrorMessage {
    param(
        [string]$ResponseText
    )

    if ([string]::IsNullOrWhiteSpace($ResponseText)) {
        return ""
    }

    try {
        $json = $ResponseText | ConvertFrom-Json

        if ($json.error.message) {
            return [string]$json.error.message
        }

        if ($json.detail) {
            return [string]$json.detail
        }

        return ($json | ConvertTo-Json -Depth 20)
    }
    catch {
        return $ResponseText
    }
}

function Invoke-LiteLLMTest {
    param(
        [string]$ModelName
    )

    $bodyObject = @{
        model       = $ModelName
        temperature = 0
        max_tokens  = 20
        messages    = @(
            @{
                role    = "user"
                content = "Responda apenas: ok"
            }
        )
    }

    $bodyJson = $bodyObject | ConvertTo-Json -Depth 20

    $tempFile = Join-Path $env:TEMP ("litellm-body-" + [Guid]::NewGuid().ToString() + ".json")

    try {
        $utf8NoBom = New-Object System.Text.UTF8Encoding $false
        [System.IO.File]::WriteAllText($tempFile, $bodyJson, $utf8NoBom)

        $args = @(
            "-sS",
            "--max-time", "$timeoutSeconds",
            "-w", "`n__HTTP_STATUS__:%{http_code}",
            "-X", "POST",
            $baseUrl,
            "-H", "Authorization: Bearer $env:REPRLLM_API_KEY",
            "-H", "Content-Type: application/json",
            "--data-binary", "@$tempFile"
        )

        if (-not [string]::IsNullOrWhiteSpace($proxyUrl)) {
            $args += @(
                "--proxy", $proxyUrl
            )
        }

        $rawOutput = & curl.exe @args 2>&1
        $rawText = ($rawOutput | Out-String).Trim()

        $statusMatch = [regex]::Match($rawText, "__HTTP_STATUS__:(\d{3})\s*$")

        if ($statusMatch.Success) {
            $statusCode = [int]$statusMatch.Groups[1].Value
            $responseText = $rawText.Substring(0, $statusMatch.Index).Trim()
        }
        else {
            $statusCode = 0
            $responseText = $rawText
        }

        if ($statusCode -ge 200 -and $statusCode -lt 300) {
            try {
                $jsonResponse = $responseText | ConvertFrom-Json
                $content = $jsonResponse.choices[0].message.content

                return [PSCustomObject]@{
                    Ok           = $true
                    StatusCode   = $statusCode
                    Content      = $content
                    ErrorSummary = ""
                    ErrorRaw     = ""
                    ResponseRaw  = $responseText
                }
            }
            catch {
                return [PSCustomObject]@{
                    Ok           = $false
                    StatusCode   = $statusCode
                    Content      = ""
                    ErrorSummary = "Resposta HTTP OK, mas não foi possível interpretar o JSON."
                    ErrorRaw     = $_.Exception.Message
                    ResponseRaw  = $responseText
                }
            }
        }
        else {
            $shortError = Get-ShortErrorMessage -ResponseText $responseText

            return [PSCustomObject]@{
                Ok           = $false
                StatusCode   = $statusCode
                Content      = ""
                ErrorSummary = $shortError
                ErrorRaw     = $responseText
                ResponseRaw  = $responseText
            }
        }
    }
    finally {
        if (Test-Path $tempFile) {
            Remove-Item $tempFile -Force -ErrorAction SilentlyContinue
        }
    }
}

# ==============================
# EXECUÇÃO DOS TESTES
# ==============================

$results = @()

Write-Host ""
Write-Host "Iniciando testes..." -ForegroundColor Cyan
Write-Host "Total de modelos: $($models.Count)" -ForegroundColor Cyan
Write-Host ""

foreach ($model in $models) {
    Write-Host "Testando: $model" -ForegroundColor Cyan

    $start = Get-Date
    $test = Invoke-LiteLLMTest -ModelName $model
    $end = Get-Date

    $durationMs = [math]::Round(($end - $start).TotalMilliseconds, 0)

    if ($test.Ok) {
        Write-Host "FUNCIONOU: $model" -ForegroundColor Green
        Write-Host "Resposta: $($test.Content)" -ForegroundColor Green
    }
    else {
        Write-Host "FALHOU: $model" -ForegroundColor DarkGray

        if (-not [string]::IsNullOrWhiteSpace($test.ErrorSummary)) {
            $summary = $test.ErrorSummary

            if ($summary.Length -gt 700) {
                $summary = $summary.Substring(0, 700) + "..."
            }

            Write-Host $summary -ForegroundColor DarkGray
        }
        else {
            Write-Host "Erro sem mensagem detalhada. HTTP Status: $($test.StatusCode)" -ForegroundColor DarkGray
        }
    }

    $results += [PSCustomObject]@{
        Modelo       = $model
        Status       = if ($test.Ok) { "OK" } else { "FALHOU" }
        HttpStatus   = $test.StatusCode
        DuracaoMs    = $durationMs
        Resposta     = $test.Content
        ErroResumo   = $test.ErrorSummary
        ErroCompleto = $test.ErrorRaw
    }

    Write-Host ""

    Start-Sleep -Seconds $pauseSeconds
}

# ==============================
# RESUMO
# ==============================

Write-Host "==============================" -ForegroundColor Green
Write-Host "RESUMO DOS MODELOS FUNCIONAIS" -ForegroundColor Green
Write-Host "==============================" -ForegroundColor Green
Write-Host ""

$okModels = $results | Where-Object { $_.Status -eq "OK" }

if ($okModels.Count -eq 0) {
    Write-Host "Nenhum modelo funcionou." -ForegroundColor Red
}
else {
    $okModels |
        Select-Object Modelo, HttpStatus, DuracaoMs, Resposta |
        Format-Table -AutoSize
}

Write-Host ""
Write-Host "==============================" -ForegroundColor Yellow
Write-Host "RESUMO DOS MODELOS COM FALHA" -ForegroundColor Yellow
Write-Host "==============================" -ForegroundColor Yellow
Write-Host ""

$failedModels = $results | Where-Object { $_.Status -eq "FALHOU" }

if ($failedModels.Count -eq 0) {
    Write-Host "Nenhum modelo falhou." -ForegroundColor Green
}
else {
    $failedModels |
        Select-Object Modelo, HttpStatus, ErroResumo |
        Format-Table -AutoSize
}

# ==============================
# SALVAR RELATÓRIOS
# ==============================

$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"

$csvPath = ".\resultado-modelos-litellm-$timestamp.csv"
$jsonPath = ".\resultado-modelos-litellm-$timestamp.json"

$results | Export-Csv -Path $csvPath -NoTypeInformation -Encoding UTF8
$results | ConvertTo-Json -Depth 50 | Out-File -FilePath $jsonPath -Encoding UTF8

Write-Host ""
Write-Host "Relatórios salvos em:" -ForegroundColor Cyan
Write-Host $csvPath -ForegroundColor Cyan
Write-Host $jsonPath -ForegroundColor Cyan