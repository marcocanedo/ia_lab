param(
    [switch]$ForceRestart
)

$ErrorActionPreference = "Stop"

$labRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$pxDirectory = Join-Path $labRoot "px"
$pxPath = Join-Path $pxDirectory "px.exe"
$pxConfigPath = Join-Path $pxDirectory "px.ini"
$port = 18080
$pxStartupTimeoutSeconds = 60
$expectedRoot = ([IO.Path]::GetFullPath($pxDirectory)).TrimEnd("\\") + "\\"
$stateDirectory = Join-Path (Split-Path $PSScriptRoot -Parent) "logs"
$pidFile = Join-Path $stateDirectory "px.pid"

function Get-ProcessSnapshot {
    $snapshot = @{}
    foreach ($process in @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue)) {
        $snapshot[[int]$process.ProcessId] = $process
    }

    return $snapshot
}

function Test-ProcessInExpectedPxDirectory {
    param(
        [object]$Process,
        [hashtable]$ProcessSnapshot
    )

    $current = $Process
    $visited = New-Object System.Collections.Generic.HashSet[int]
    $knownRootId = 0

    if (Test-Path -LiteralPath $pidFile) {
        [int]::TryParse((Get-Content -LiteralPath $pidFile -Raw).Trim(), [ref]$knownRootId) | Out-Null
    }

    while ($current -and $visited.Add([int]$current.ProcessId)) {
        $executablePath = [string]$current.ExecutablePath
        $commandLine = [string]$current.CommandLine

        # O launcher congelado do PX pode ocultar ExecutablePath/CommandLine
        # para o usuario comum. O PID persistido evita classificar esse caso
        # como um PX estranho e reinicia-lo a cada logon.
        if ($knownRootId -gt 0 -and [int]$current.ProcessId -eq $knownRootId) {
            return $true
        }

        if ($executablePath.StartsWith($expectedRoot, [StringComparison]::OrdinalIgnoreCase) -or
            $commandLine.IndexOf($pxPath, [StringComparison]::OrdinalIgnoreCase) -ge 0) {
            return $true
        }

        $current = $ProcessSnapshot[[int]$current.ParentProcessId]
    }

    return $false
}

function Get-PxListeners {
    return @(Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction SilentlyContinue)
}

function Test-ExpectedPxListener {
    $processSnapshot = Get-ProcessSnapshot
    $listeners = @(Get-PxListeners)
    if ($listeners.Count -eq 0) {
        return $false
    }

    foreach ($listener in $listeners) {
        $owner = $processSnapshot[[int]$listener.OwningProcess]
        if (-not $owner -or -not (Test-ProcessInExpectedPxDirectory -Process $owner -ProcessSnapshot $processSnapshot)) {
            return $false
        }
    }

    return $true
}

function Test-PxPortReady {
    try {
        return ((Test-NetConnection 127.0.0.1 -Port $port -InformationLevel Quiet -WarningAction SilentlyContinue) -and
            (Test-ExpectedPxListener))
    }
    catch {
        return $false
    }
}

function Get-IaLabPxProcessIds {
    $snapshot = Get-ProcessSnapshot
    $rootIds = New-Object System.Collections.Generic.HashSet[int]

    foreach ($process in $snapshot.Values) {
        $executablePath = [string]$process.ExecutablePath
        $commandLine = [string]$process.CommandLine
        if ($executablePath -match '(?i)\\px\\px\.exe$' -or $commandLine -match '(?i)\\px\\px\.exe') {
            $null = $rootIds.Add([int]$process.ProcessId)
        }
    }

    $allIds = New-Object System.Collections.Generic.HashSet[int]
    foreach ($rootId in $rootIds) {
        $null = $allIds.Add($rootId)
    }

    $added = $true
    while ($added) {
        $added = $false
        foreach ($process in $snapshot.Values) {
            if ($allIds.Contains([int]$process.ParentProcessId) -and $allIds.Add([int]$process.ProcessId)) {
                $added = $true
            }
        }
    }

    return @($allIds)
}

function Stop-IaLabPxProcesses {
    $processIds = @(Get-IaLabPxProcessIds)
    if ($processIds.Count -eq 0) {
        return
    }

    Write-Host ("Encerrando processos PX conflitantes: {0}" -f ($processIds -join ", "))
    foreach ($processId in ($processIds | Sort-Object -Descending)) {
        Stop-Process -Id $processId -Force -ErrorAction SilentlyContinue
    }

    Remove-Item -LiteralPath $pidFile -Force -ErrorAction SilentlyContinue

    $deadline = (Get-Date).AddSeconds(15)
    while ((Get-Date) -lt $deadline) {
        if ((Get-PxListeners).Count -eq 0) {
            return
        }

        Start-Sleep -Milliseconds 500
    }

    throw "A porta $port continuou ocupada apos encerrar os processos PX."
}

function Wait-ForExpectedPxPort {
    param(
        [int]$TimeoutSeconds = $pxStartupTimeoutSeconds
    )

    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    while ((Get-Date) -lt $deadline) {
        if (Test-PxPortReady) {
            return $true
        }

        Start-Sleep -Seconds 1
    }

    return $false
}

Write-Host "Iniciando PX..."
Write-Host "PX executavel: $pxPath"

foreach ($requiredPath in @($pxDirectory, $pxPath, $pxConfigPath)) {
    if (-not (Test-Path -LiteralPath $requiredPath)) {
        throw "PX nao encontrado ou incompleto: $requiredPath"
    }
}

if ((Test-PxPortReady) -and -not $ForceRestart) {
    Write-Host "PX de D:\\IA-LAB ja esta pronto em 127.0.0.1:$port"
    return
}

if ((Get-PxListeners).Count -gt 0) {
    Write-Host "A porta $port esta ocupada por um PX que nao pertence a D:\\IA-LAB."
}

Stop-IaLabPxProcesses

# px.exe e um launcher Python. Ao priorizar a pasta local no PATH, os workers
# sempre usam D:\IA-LAB\px\python.exe, sem herdar um runtime antigo de C:.
$env:PATH = "$pxDirectory;$env:PATH"
$arguments = @(
    "--config=$pxConfigPath",
    # O hostonly desta versao aceita a conexao TCP das VMs, mas encerra a
    # requisicao HTTP. Gateway + allow explicito libera apenas loopback e as
    # redes NAT privadas usadas pelo WSL/Hyper-V, inclusive apos troca de IP.
    "--gateway=1",
    "--allow=127.0.0.1,172.16.0.0/12",
    "--port=$port"
)

$startedProcess = Start-Process -FilePath $pxPath -ArgumentList $arguments -WorkingDirectory $pxDirectory -WindowStyle Hidden -PassThru
New-Item -ItemType Directory -Path $stateDirectory -Force | Out-Null
Set-Content -LiteralPath $pidFile -Value $startedProcess.Id -Encoding Ascii
Write-Host "PX iniciado com PID $($startedProcess.Id); aguardando a porta $port..."

if (Wait-ForExpectedPxPort) {
    Write-Host "PX de D:\\IA-LAB pronto em 127.0.0.1:$port"
    return
}

Stop-IaLabPxProcesses
throw "PX de D:\\IA-LAB nao abriu a porta $port dentro de $pxStartupTimeoutSeconds segundos"
