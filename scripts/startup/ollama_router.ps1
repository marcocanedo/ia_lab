$ErrorActionPreference = "Stop"

$listenPort = 11436
$gpuHost = "127.0.0.1"
$gpuPort = 11434
$cpuHost = "127.0.0.1"
$cpuPort = 11435

$cpuModels = @{
    "gemma3:4b" = $true
    "qwen2.5:3b" = $true
}

$gpuModels = @{
    "smollm2:135m" = $true
    "llama3.2:3b" = $true
    "qwen3.5:0.8b" = $true
    "gemma4:12b" = $true
    "gemma4:12b-gpu" = $true
    "gemma4:12b-it-q4_K_M" = $true
}

$upstreamModelAliases = @{
    "gemma4:12b" = "gemma4:12b-gpu"
}

$hiddenDisplayModels = @{
    "gemma4:12b-gpu" = $true
    "gemma4:12b-it-q4_K_M" = $true
}

$displaySuffixPattern = "\s+\[(GPU|CPU)\]$"

function Resolve-ModelName {
    param([string]$Model)

    if (-not $Model) {
        return $Model
    }

    return ($Model -replace $displaySuffixPattern, "")
}

function Resolve-UpstreamModelName {
    param([string]$Model)

    $canonical = Resolve-ModelName $Model
    if ($upstreamModelAliases.ContainsKey($canonical)) {
        return $upstreamModelAliases[$canonical]
    }

    return $canonical
}

function Get-ModelBackendLabel {
    param([string]$Model)

    $canonical = Resolve-ModelName $Model
    if ($cpuModels.ContainsKey($canonical)) {
        return "CPU"
    }

    return "GPU"
}

function Get-DisplayModelName {
    param([string]$Model)

    $canonical = Resolve-ModelName $Model
    $backend = Get-ModelBackendLabel $canonical
    return "$canonical [$backend]"
}

function Get-ModelBackendDescription {
    param([string]$Model)

    $backend = Get-ModelBackendLabel $Model
    if ($backend -eq "CPU") {
        return "IA-LAB backend: CPU via Ollama 11435"
    }

    return "IA-LAB backend: GPU via Ollama 11434"
}

function Read-HttpLine {
    param([System.IO.Stream]$Stream)

    $bytes = New-Object System.Collections.Generic.List[byte]
    while ($true) {
        $value = $Stream.ReadByte()
        if ($value -lt 0) {
            break
        }
        if ($value -eq 10) {
            break
        }
        if ($value -ne 13) {
            $bytes.Add([byte]$value)
        }
    }

    return [System.Text.Encoding]::ASCII.GetString($bytes.ToArray())
}

function Get-Backend {
    param([string]$Body)

    try {
        if ($Body) {
            $payload = $Body | ConvertFrom-Json -ErrorAction Stop
            $model = Resolve-ModelName ([string]$payload.model)
            if ($cpuModels.ContainsKey($model)) {
                Write-Host "$(Get-Date -Format s) route model=$model backend=cpu"
                return @{ host = $cpuHost; port = $cpuPort }
            }
            if ($gpuModels.ContainsKey($model)) {
                Write-Host "$(Get-Date -Format s) route model=$model backend=gpu"
                return @{ host = $gpuHost; port = $gpuPort }
            }
        }
    }
    catch {
        Write-Host "$(Get-Date -Format s) route parse failed: $($_.Exception.Message)"
    }

    Write-Host "$(Get-Date -Format s) route model=- backend=gpu"
    return @{ host = $gpuHost; port = $gpuPort }
}

function Update-RequestBodyModel {
    param([string]$Body)

    if (-not $Body) {
        return $Body
    }

    try {
        $payload = $Body | ConvertFrom-Json -ErrorAction Stop
        if ($payload.PSObject.Properties.Name -contains "model") {
            $payload.model = Resolve-UpstreamModelName ([string]$payload.model)
            return ($payload | ConvertTo-Json -Depth 64 -Compress)
        }
    }
    catch {
        Write-Host "$(Get-Date -Format s) model rewrite skipped: $($_.Exception.Message)"
    }

    return $Body
}

function Copy-UntilClosed {
    param(
        [System.IO.Stream]$InputStream,
        [System.IO.Stream]$OutputStream
    )

    $buffer = New-Object byte[] 65536
    while (($read = $InputStream.Read($buffer, 0, $buffer.Length)) -gt 0) {
        $OutputStream.Write($buffer, 0, $read)
        $OutputStream.Flush()
    }
}

function Write-ErrorResponse {
    param([System.IO.Stream]$Stream, [string]$Message)

    $body = [System.Text.Encoding]::UTF8.GetBytes("{`"error`":`"$Message`"}")
    $header = "HTTP/1.1 502 Bad Gateway`r`nContent-Type: application/json`r`nContent-Length: $($body.Length)`r`nConnection: close`r`n`r`n"
    $headerBytes = [System.Text.Encoding]::ASCII.GetBytes($header)
    $Stream.Write($headerBytes, 0, $headerBytes.Length)
    $Stream.Write($body, 0, $body.Length)
    $Stream.Flush()
}

function Write-JsonResponse {
    param([System.IO.Stream]$Stream, [string]$Json)

    $body = [System.Text.Encoding]::UTF8.GetBytes($Json)
    $header = "HTTP/1.1 200 OK`r`nContent-Type: application/json`r`nContent-Length: $($body.Length)`r`nConnection: close`r`n`r`n"
    $headerBytes = [System.Text.Encoding]::ASCII.GetBytes($header)
    $Stream.Write($headerBytes, 0, $headerBytes.Length)
    $Stream.Write($body, 0, $body.Length)
    $Stream.Flush()
}

function Write-TaggedModelsResponse {
    param([System.IO.Stream]$Stream)

    $uri = "http://{0}:{1}/api/tags" -f $gpuHost, $gpuPort
    $tags = Invoke-RestMethod -Uri $uri -TimeoutSec 30
    $visibleModels = @()

    foreach ($modelInfo in @($tags.models)) {
        $canonical = Resolve-ModelName ([string]$modelInfo.name)
        if (-not $canonical) {
            $canonical = Resolve-ModelName ([string]$modelInfo.model)
        }

        if ($hiddenDisplayModels.ContainsKey($canonical)) {
            continue
        }

        $displayName = Get-DisplayModelName $canonical
        $description = Get-ModelBackendDescription $canonical

        if ($modelInfo.PSObject.Properties.Name -contains "name") {
            $modelInfo.name = $displayName
        }
        if ($modelInfo.PSObject.Properties.Name -contains "model") {
            $modelInfo.model = $displayName
        }

        $modelInfo | Add-Member -NotePropertyName "description" -NotePropertyValue $description -Force
        $modelInfo | Add-Member -NotePropertyName "ia_lab_backend" -NotePropertyValue (Get-ModelBackendLabel $canonical) -Force
        $modelInfo | Add-Member -NotePropertyName "ia_lab_model" -NotePropertyValue $canonical -Force

        if (-not $modelInfo.details) {
            $modelInfo | Add-Member -NotePropertyName "details" -NotePropertyValue ([pscustomobject]@{}) -Force
        }

        $modelInfo.details | Add-Member -NotePropertyName "description" -NotePropertyValue $description -Force
        $modelInfo.details | Add-Member -NotePropertyName "ia_lab_backend" -NotePropertyValue (Get-ModelBackendLabel $canonical) -Force
        $visibleModels += $modelInfo
    }

    $tags.models = @($visibleModels)
    $json = $tags | ConvertTo-Json -Depth 12 -Compress
    Write-JsonResponse $Stream $json
}

$listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Any, $listenPort)
$listener.Start()
Write-Host "$(Get-Date -Format s) ollama router listening on 0.0.0.0:$listenPort"

while ($true) {
    $client = $listener.AcceptTcpClient()
    $client.NoDelay = $true

    try {
        $clientStream = $client.GetStream()
        $requestLine = Read-HttpLine $clientStream
        if (-not $requestLine) {
            $client.Close()
            continue
        }

        $headers = [ordered]@{}
        while ($true) {
            $line = Read-HttpLine $clientStream
            if ($line -eq "") {
                break
            }
            $parts = $line -split ":", 2
            if ($parts.Count -eq 2) {
                $headers[$parts[0].Trim()] = $parts[1].Trim()
            }
        }

        $contentLength = 0
        foreach ($key in $headers.Keys) {
            if ($key -ieq "Content-Length") {
                [int]::TryParse($headers[$key], [ref]$contentLength) | Out-Null
            }
        }

        $bodyBytes = New-Object byte[] $contentLength
        $offset = 0
        while ($offset -lt $contentLength) {
            $offset += $clientStream.Read($bodyBytes, $offset, $contentLength - $offset)
        }
        $body = [System.Text.Encoding]::UTF8.GetString($bodyBytes)

        if ($requestLine.StartsWith("GET /api/tags")) {
            Write-TaggedModelsResponse $clientStream
            continue
        }

        if ($requestLine.StartsWith("POST ")) {
            $body = Update-RequestBodyModel $body
            $bodyBytes = [System.Text.Encoding]::UTF8.GetBytes($body)
            $contentLength = $bodyBytes.Length
        }

        $backend = if ($requestLine.StartsWith("POST ")) {
            Get-Backend $body
        }
        else {
            @{ host = $gpuHost; port = $gpuPort }
        }

        $upstream = [System.Net.Sockets.TcpClient]::new($backend.host, $backend.port)
        $upstream.NoDelay = $true
        $upstreamStream = $upstream.GetStream()

        $requestBuilder = [System.Text.StringBuilder]::new()
        [void]$requestBuilder.Append($requestLine).Append("`r`n")
        [void]$requestBuilder.Append("Host: $($backend.host):$($backend.port)`r`n")
        [void]$requestBuilder.Append("Connection: close`r`n")
        foreach ($key in $headers.Keys) {
            if ($key -notin @("Host", "Connection", "Content-Length", "Transfer-Encoding")) {
                [void]$requestBuilder.Append($key).Append(": ").Append($headers[$key]).Append("`r`n")
            }
        }
        if ($contentLength -gt 0) {
            [void]$requestBuilder.Append("Content-Length: $contentLength`r`n")
        }
        [void]$requestBuilder.Append("`r`n")

        $requestBytes = [System.Text.Encoding]::ASCII.GetBytes($requestBuilder.ToString())
        $upstreamStream.Write($requestBytes, 0, $requestBytes.Length)
        if ($contentLength -gt 0) {
            $upstreamStream.Write($bodyBytes, 0, $bodyBytes.Length)
        }
        $upstreamStream.Flush()

        Copy-UntilClosed $upstreamStream $clientStream
        $upstream.Close()
    }
    catch {
        try {
            Write-ErrorResponse $client.GetStream() $_.Exception.Message
        }
        catch {}
    }
    finally {
        $client.Close()
    }
}
