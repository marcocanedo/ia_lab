param(
    [string]$OutputDir = "C:\inventario_migracao_workstation",
    [int]$UninstallTimeoutSeconds = 180,
    [switch]$DryRun
)

$ErrorActionPreference = "Continue"
$ProgressPreference = "Continue"

$runStamp = Get-Date -Format "yyyyMMdd_HHmmss"
$preDir = Join-Path $OutputDir "pre_remocao"
$postDir = Join-Path $OutputDir "pos_remocao"
$runDir = Join-Path $OutputDir "fase3_verbose_$runStamp"
$logPath = Join-Path $runDir "fase3_verbose.log"
$checkpointPath = Join-Path $runDir "checkpoint.jsonl"

New-Item -ItemType Directory -Force -Path $OutputDir, $preDir, $postDir, $runDir | Out-Null

function Format-Bytes {
    param([double]$Bytes)
    if ($Bytes -ge 1GB) { return "{0:N2} GB" -f ($Bytes / 1GB) }
    if ($Bytes -ge 1MB) { return "{0:N2} MB" -f ($Bytes / 1MB) }
    if ($Bytes -ge 1KB) { return "{0:N2} KB" -f ($Bytes / 1KB) }
    return "{0:N0} B" -f $Bytes
}

function Escape-Md {
    param([object]$Value)
    if ($null -eq $Value) { return "" }
    return ([string]$Value).Replace("|", "\|").Replace("`r", " ").Replace("`n", " ").Trim()
}

function Write-Utf8 {
    param([string]$Path, [string[]]$Lines)
    $Lines | Set-Content -Encoding UTF8 -Path $Path
}

function Write-Step {
    param([string]$Message, [string]$Level = "INFO")
    $line = "{0} [{1}] {2}" -f (Get-Date -Format s), $Level, $Message
    Add-Content -Encoding UTF8 -Path $logPath -Value $line
    Write-Host $line
}

function Write-Checkpoint {
    param([hashtable]$Data)
    $Data["time"] = (Get-Date).ToString("s")
    $Data | ConvertTo-Json -Compress -Depth 6 | Add-Content -Encoding UTF8 -Path $checkpointPath
}

function Get-InstalledPrograms {
    Get-ItemProperty `
        "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*", `
        "HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*", `
        "HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*" `
        -ErrorAction SilentlyContinue |
        Where-Object DisplayName |
        Select-Object DisplayName, DisplayVersion, Publisher, InstallDate, InstallLocation, UninstallString, QuietUninstallString, PSPath |
        Sort-Object DisplayName
}

function Export-Snapshot {
    param([string]$Dir, [string]$Label)
    Write-Step "[$Label] Exportando programas, servicos, tarefas, processos e winget para $Dir"
    New-Item -ItemType Directory -Force -Path $Dir | Out-Null
    Get-InstalledPrograms | Export-Csv -NoTypeInformation -Encoding UTF8 -Path (Join-Path $Dir "programas_instalados.csv")
    Get-Service | Select-Object Name, DisplayName, Status, StartType, ServiceType |
        Export-Csv -NoTypeInformation -Encoding UTF8 -Path (Join-Path $Dir "servicos.csv")
    Get-ScheduledTask -ErrorAction SilentlyContinue |
        Select-Object TaskName, TaskPath, State, Author, Description |
        Export-Csv -NoTypeInformation -Encoding UTF8 -Path (Join-Path $Dir "tarefas_agendadas.csv")
    Get-Process | Select-Object ProcessName, Id, Path, WorkingSet64 |
        Export-Csv -NoTypeInformation -Encoding UTF8 -Path (Join-Path $Dir "processos.csv")
    if (Get-Command winget -ErrorAction SilentlyContinue) {
        winget list | Set-Content -Encoding UTF8 -Path (Join-Path $Dir "winget_list.txt")
    }
}

function Get-UninstallCommand {
    param([object]$Program)
    $display = [string]$Program.DisplayName
    $cmd = if ($Program.QuietUninstallString) { [string]$Program.QuietUninstallString } else { [string]$Program.UninstallString }
    if (-not $cmd) { return $null }

    $file = ""
    $args = ""
    if ($cmd -match '^\s*"([^"]+)"\s*(.*)$') {
        $file = $matches[1]
        $args = $matches[2]
    }
    elseif ($cmd -match '^\s*([^\s]+)\s*(.*)$') {
        $file = $matches[1]
        $args = $matches[2]
    }

    if ($file -match "(?i)msiexec(\.exe)?$" -or $cmd -match "(?i)MsiExec") {
        if ($cmd -match "\{[0-9A-Fa-f-]{36}\}") {
            $file = "msiexec.exe"
            $args = "/x $($matches[0]) /qn /norestart"
        }
    }
    elseif (-not $Program.QuietUninstallString) {
        $lower = $display.ToLowerInvariant()
        if ($lower -match "teamviewer") { $args = "$args /S" }
        elseif ($lower -match "anyviewer|iobit|advanced systemcare|itop|atom|foxit|mobizen|silverlight|virtualbox") {
            $args = "$args /S /silent /verysilent /norestart"
        }
    }

    [pscustomobject]@{ File = $file; Args = $args; Original = $cmd }
}

function Invoke-UninstallVerbose {
    param([object]$Program)
    $display = [string]$Program.DisplayName
    $cmd = Get-UninstallCommand $Program
    if (-not $cmd) {
        Write-Step "Sem desinstalador registrado: $display" "WARN"
        return [pscustomobject]@{ Name = $display; Status = "sem uninstallstring"; ExitCode = ""; Detail = "" }
    }

    Write-Step "Preparando desinstalacao: $display"
    Write-Step "Comando original: $($cmd.Original)"
    Write-Step "Executavel: $($cmd.File)"
    Write-Step "Argumentos: $($cmd.Args)"
    Write-Checkpoint @{ phase = "uninstall_start"; name = $display; file = $cmd.File; args = $cmd.Args }

    if ($DryRun) {
        Write-Step "DRY-RUN: nao executado: $display" "WARN"
        return [pscustomobject]@{ Name = $display; Status = "dry-run"; ExitCode = ""; Detail = "$($cmd.File) $($cmd.Args)" }
    }

    try {
        $proc = Start-Process -FilePath $cmd.File -ArgumentList $cmd.Args -PassThru -WindowStyle Hidden -ErrorAction Stop
        Write-Step "Processo iniciado: PID=$($proc.Id), timeout=${UninstallTimeoutSeconds}s"
        $finished = $proc.WaitForExit($UninstallTimeoutSeconds * 1000)
        if (-not $finished) {
            Write-Step "Timeout no desinstalador: $display. Nao matei o processo automaticamente; seguindo adiante." "WARN"
            Write-Checkpoint @{ phase = "uninstall_timeout"; name = $display; pid = $proc.Id }
            return [pscustomobject]@{ Name = $display; Status = "timeout"; ExitCode = ""; Detail = "PID $($proc.Id) excedeu ${UninstallTimeoutSeconds}s" }
        }
        Write-Step "Concluido: $display ExitCode=$($proc.ExitCode)"
        Write-Checkpoint @{ phase = "uninstall_end"; name = $display; exit_code = $proc.ExitCode }
        return [pscustomobject]@{ Name = $display; Status = "executado"; ExitCode = $proc.ExitCode; Detail = "$($cmd.File) $($cmd.Args)" }
    }
    catch {
        Write-Step "Falha ao executar desinstalador de ${display}: $($_.Exception.Message)" "ERROR"
        Write-Checkpoint @{ phase = "uninstall_error"; name = $display; error = $_.Exception.Message }
        return [pscustomobject]@{ Name = $display; Status = "falhou"; ExitCode = ""; Detail = $_.Exception.Message }
    }
}

function Remove-FileVerbose {
    param([string]$Path, [string]$Reason)
    $exists = Test-Path -LiteralPath $Path
    if (-not $exists) {
        Write-Step "Arquivo nao encontrado: $Path"
        return [pscustomobject]@{ Path = $Path; Status = "nao encontrado"; Bytes = 0; Reason = $Reason; Error = "" }
    }
    $size = (Get-Item -LiteralPath $Path -Force).Length
    Write-Step "Arquivo alvo: $Path ($size bytes / $(Format-Bytes $size)) - $Reason"
    Write-Checkpoint @{ phase = "delete_file_start"; path = $Path; bytes = $size; reason = $Reason }
    if ($DryRun) {
        Write-Step "DRY-RUN: nao apagado: $Path" "WARN"
        return [pscustomobject]@{ Path = $Path; Status = "dry-run"; Bytes = $size; Reason = $Reason; Error = "" }
    }
    try {
        Remove-Item -LiteralPath $Path -Force -ErrorAction Stop
        Write-Step "Arquivo apagado: $Path"
        Write-Checkpoint @{ phase = "delete_file_end"; path = $Path; bytes = $size }
        return [pscustomobject]@{ Path = $Path; Status = "apagado"; Bytes = $size; Reason = $Reason; Error = "" }
    }
    catch {
        Write-Step "Falha apagando arquivo ${Path}: $($_.Exception.Message)" "ERROR"
        return [pscustomobject]@{ Path = $Path; Status = "falhou"; Bytes = $size; Reason = $Reason; Error = $_.Exception.Message }
    }
}

function Remove-TaskVerbose {
    param([object]$Task)
    $name = "$($Task.TaskPath)$($Task.TaskName)"
    Write-Step "Tarefa alvo: $name"
    if ($DryRun) {
        Write-Step "DRY-RUN: tarefa nao removida: $name" "WARN"
        return [pscustomobject]@{ Task = $name; Status = "dry-run"; Error = "" }
    }
    try {
        Unregister-ScheduledTask -TaskName $Task.TaskName -TaskPath $Task.TaskPath -Confirm:$false -ErrorAction Stop
        Write-Step "Tarefa removida: $name"
        return [pscustomobject]@{ Task = $name; Status = "removida"; Error = "" }
    }
    catch {
        Write-Step "Falha removendo tarefa ${name}: $($_.Exception.Message)" "ERROR"
        return [pscustomobject]@{ Task = $name; Status = "falhou"; Error = $_.Exception.Message }
    }
}

function Write-Report {
    param([object[]]$Uninstalls, [object[]]$Files, [object[]]$Tasks)
    $spaceRecovered = [long](($Files | Where-Object Status -eq "apagado" | Measure-Object Bytes -Sum).Sum)
    $lines = @()
    $lines += "# Relatorio pos-remocao"
    $lines += ""
    $lines += "Gerado em: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
    $lines += "Run dir: $runDir"
    $lines += "DryRun: $DryRun"
    $lines += ""
    $lines += "## Espaco recuperado"
    $lines += ""
    $lines += "- $(Format-Bytes $spaceRecovered)"
    $lines += "- $spaceRecovered bytes"
    $lines += ""
    $lines += "## Programas removidos / tentados"
    $lines += ""
    $lines += "| Programa | Status | ExitCode | Detalhe |"
    $lines += "|---|---|---:|---|"
    foreach ($u in $Uninstalls) {
        $lines += "| $(Escape-Md $u.Name) | $(Escape-Md $u.Status) | $(Escape-Md $u.ExitCode) | $(Escape-Md $u.Detail) |"
    }
    $lines += ""
    $lines += "## Arquivos apagados / tentados"
    $lines += ""
    $lines += "| Arquivo | Status | Tamanho | Motivo | Erro |"
    $lines += "|---|---|---:|---|---|"
    foreach ($f in $Files) {
        $lines += "| $(Escape-Md $f.Path) | $(Escape-Md $f.Status) | $(Format-Bytes $f.Bytes) | $(Escape-Md $f.Reason) | $(Escape-Md $f.Error) |"
    }
    $lines += ""
    $lines += "## Tarefas removidas / tentadas"
    $lines += ""
    $lines += "| Tarefa | Status | Erro |"
    $lines += "|---|---|---|"
    foreach ($t in $Tasks) {
        $lines += "| $(Escape-Md $t.Task) | $(Escape-Md $t.Status) | $(Escape-Md $t.Error) |"
    }
    Write-Utf8 (Join-Path $OutputDir "relatorio_pos_remocao.md") $lines
}

$protectedPattern = "(?i)\b(AnyDesk|BRy|SafeNet|Receita|SEFA|SEFAZ|IA-LAB|Docker|WSL|Hyper-V|Ollama|Open WebUI|Python|Conda|Anaconda|Visual Studio Code|VS Code|Git)\b"
$targets = @(
    "TeamViewer", "AnyViewer", "Advanced SystemCare", "iTop Easy Desktop", "iTop Data Recovery",
    "iTop Screen Recorder", "iTop VPN", "Atom", "Bizagi Modeler", "Mobizen", "Microsoft Silverlight",
    "Foxit Reader", "Java 8 Update 161", "Java 10", "MicroStrategy Desktop", "VirtualBox"
)

Write-Step "FASE 3 verbose iniciada. DryRun=$DryRun Timeout=${UninstallTimeoutSeconds}s"
Export-Snapshot $preDir "pre"

$prePrograms = @(Get-InstalledPrograms)
$preTasks = @(Get-ScheduledTask -ErrorAction SilentlyContinue)

$preLines = @()
$preLines += "# Relatorio pre-remocao"
$preLines += ""
$preLines += "Gerado em: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
$preLines += "Run dir: $runDir"
$preLines += ""
$preLines += "- Programas instalados exportados: $($prePrograms.Count)"
$preLines += "- Servicos exportados em: $preDir\servicos.csv"
$preLines += "- Tarefas exportadas em: $preDir\tarefas_agendadas.csv"
$preLines += ""
$preLines += "## Alvos"
foreach ($target in $targets) { $preLines += "- $target" }
Write-Utf8 (Join-Path $OutputDir "relatorio_pre_remocao.md") $preLines

$uninstallResults = @()
foreach ($target in $targets) {
    Write-Step "==== Procurando alvo: $target ===="
    $matches = @($prePrograms | Where-Object { $_.DisplayName -like "*$target*" })
    if ($target -eq "Java 10") {
        $matches = @($prePrograms | Where-Object { $_.DisplayName -match "^Java 10|Development Kit 10" })
    }
    if ($target -eq "VirtualBox") {
        $matches = @($prePrograms | Where-Object { $_.DisplayName -match "VirtualBox" })
    }
    if ($matches.Count -eq 0) {
        Write-Step "Nao encontrado: $target"
        $uninstallResults += [pscustomobject]@{ Name = $target; Status = "nao encontrado"; ExitCode = ""; Detail = "" }
        continue
    }
    foreach ($program in $matches) {
        if ($program.DisplayName -match $protectedPattern) {
            Write-Step "Protegido pela lista NAO tocar, ignorando: $($program.DisplayName)" "WARN"
            $uninstallResults += [pscustomobject]@{ Name = $program.DisplayName; Status = "protegido - ignorado"; ExitCode = ""; Detail = "Casou com lista NAO tocar" }
            continue
        }
        $uninstallResults += Invoke-UninstallVerbose $program
    }
}

$fileResults = @()
$oneDriveCorp = Get-ChildItem -LiteralPath $env:USERPROFILE -Directory -Force -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -like "OneDrive - Secretaria da Fazenda*" } |
    Select-Object -First 1 -ExpandProperty FullName
$downloads = Join-Path $env:USERPROFILE "Downloads"
$explicitFiles = @()
if ($oneDriveCorp) {
    $explicitFiles += Join-Path $oneDriveCorp "backup\20250207210629.PCT"
    $explicitFiles += Join-Path $oneDriveCorp "backup\open.tar"
}
$explicitFiles += Join-Path $downloads "imagem-base.tar"
$explicitFiles += Join-Path $downloads "imagem-base.zip"
foreach ($path in $explicitFiles) {
    $fileResults += Remove-FileVerbose $path "arquivo explicitamente solicitado"
}

if (Test-Path $downloads) {
    foreach ($pattern in @("VirtualBox-*.exe", "TeamViewer*.exe", "AnyViewer*.exe", "iTop*.exe", "Atom*.exe", "Bizagi*.exe", "Mobizen*.exe", "Silverlight*.exe", "Foxit*.exe", "MicroStrategy*.exe")) {
        Write-Step "Procurando instaladores em Downloads: $pattern"
        Get-ChildItem -LiteralPath $downloads -Filter $pattern -File -Force -ErrorAction SilentlyContinue |
            ForEach-Object { $fileResults += Remove-FileVerbose $_.FullName "instalador antigo em Downloads associado aos softwares removidos" }
    }
}

$taskResults = @()
$taskPatterns = "TeamViewer|AnyViewer|Advanced SystemCare|IObit|iTop|Atom|Bizagi|Mobizen|Silverlight|Foxit|MicroStrategy|VirtualBox"
$tasks = $preTasks | Where-Object {
    ($_.TaskName -match $taskPatterns -or $_.TaskPath -match $taskPatterns -or ($_.Actions | Out-String) -match $taskPatterns) -and
    ($_.TaskName -notmatch "AnyDesk|BRy|SafeNet|Receita|SEFA|IA-LAB|Docker|Ollama|Python|Git")
}
foreach ($task in $tasks) {
    $taskResults += Remove-TaskVerbose $task
}

Export-Snapshot $postDir "post"
Write-Report $uninstallResults $fileResults $taskResults
Write-Step "FASE 3 verbose concluida"
Write-Output "Relatorios:"
Write-Output (Join-Path $OutputDir "relatorio_pre_remocao.md")
Write-Output (Join-Path $OutputDir "relatorio_pos_remocao.md")
Write-Output "Log verbose: $logPath"
