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
            $model = [string]$payload.model
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
