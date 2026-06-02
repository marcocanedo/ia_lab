param(
    [string]$OutputDir = "C:\inventario_migracao_workstation"
)

$ErrorActionPreference = "Continue"
$ProgressPreference = "SilentlyContinue"

$preDir = Join-Path $OutputDir "pre_remocao"
$postDir = Join-Path $OutputDir "pos_remocao"
$logPath = Join-Path $OutputDir "fase3_limpeza_controlada.log"

New-Item -ItemType Directory -Force -Path $preDir, $postDir | Out-Null

function Write-Log {
    param([string]$Message)
    $line = "{0} {1}" -f (Get-Date -Format s), $Message
    Add-Content -Encoding UTF8 -Path $logPath -Value $line
    Write-Output $line
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
    param([string]$Dir)
    Write-Log "Exportando snapshot em $Dir"
    New-Item -ItemType Directory -Force -Path $Dir | Out-Null

    Get-InstalledPrograms | Export-Csv -NoTypeInformation -Encoding UTF8 -Path (Join-Path $Dir "programas_instalados.csv")
    Get-Service | Select-Object Name, DisplayName, Status, StartType, ServiceType |
        Export-Csv -NoTypeInformation -Encoding UTF8 -Path (Join-Path $Dir "servicos.csv")
    Get-ScheduledTask -ErrorAction SilentlyContinue |
        Select-Object TaskName, TaskPath, State, Author, Description |
        Export-Csv -NoTypeInformation -Encoding UTF8 -Path (Join-Path $Dir "tarefas_agendadas.csv")

    if (Get-Command winget -ErrorAction SilentlyContinue) {
        winget list | Set-Content -Encoding UTF8 -Path (Join-Path $Dir "winget_list.txt")
    }

    Get-Process | Select-Object ProcessName, Id, Path, WorkingSet64 |
        Export-Csv -NoTypeInformation -Encoding UTF8 -Path (Join-Path $Dir "processos.csv")
}

function Get-FileLengthSafe {
    param([string]$Path)
    try {
        if (Test-Path -LiteralPath $Path) {
            return (Get-Item -LiteralPath $Path -Force).Length
        }
    }
    catch {}
    return 0L
}

function Invoke-UninstallString {
    param([object]$Program)

    $display = [string]$Program.DisplayName
    $cmd = if ($Program.QuietUninstallString) { [string]$Program.QuietUninstallString } else { [string]$Program.UninstallString }
    if (-not $cmd) {
        return [pscustomobject]@{ Name = $display; Status = "falhou"; Detail = "Sem UninstallString"; ExitCode = "" }
    }

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
            $productCode = $matches[0]
            $file = "msiexec.exe"
            $args = "/x $productCode /qn /norestart"
        }
    }
    elseif (-not $Program.QuietUninstallString) {
        $lower = $display.ToLowerInvariant()
        if ($lower -match "teamviewer") { $args = "$args /S" }
        elseif ($lower -match "anyviewer|iobit|advanced systemcare|itop|atom|foxit|mobizen|silverlight|virtualbox") { $args = "$args /S /silent /verysilent /norestart" }
    }

    try {
        Write-Log "Desinstalando: $display :: $file $args"
        $p = Start-Process -FilePath $file -ArgumentList $args -Wait -PassThru -WindowStyle Hidden -ErrorAction Stop
        return [pscustomobject]@{ Name = $display; Status = "executado"; Detail = "$file $args"; ExitCode = $p.ExitCode }
    }
    catch {
        return [pscustomobject]@{ Name = $display; Status = "falhou"; Detail = $_.Exception.Message; ExitCode = "" }
    }
}

function Remove-FileControlled {
    param([string]$Path, [string]$Reason)
    $size = Get-FileLengthSafe $Path
    if (-not (Test-Path -LiteralPath $Path)) {
        return [pscustomobject]@{ Path = $Path; Status = "nao encontrado"; Bytes = 0; Reason = $Reason; Error = "" }
    }
    try {
        Write-Log "Apagando arquivo: $Path"
        Remove-Item -LiteralPath $Path -Force -ErrorAction Stop
        return [pscustomobject]@{ Path = $Path; Status = "apagado"; Bytes = $size; Reason = $Reason; Error = "" }
    }
    catch {
        return [pscustomobject]@{ Path = $Path; Status = "falhou"; Bytes = $size; Reason = $Reason; Error = $_.Exception.Message }
    }
}

function Remove-TaskControlled {
    param([Microsoft.Management.Infrastructure.CimInstance]$Task)
    try {
        Write-Log "Removendo tarefa: $($Task.TaskPath)$($Task.TaskName)"
        Unregister-ScheduledTask -TaskName $Task.TaskName -TaskPath $Task.TaskPath -Confirm:$false -ErrorAction Stop
        return [pscustomobject]@{ Task = "$($Task.TaskPath)$($Task.TaskName)"; Status = "removida"; Error = "" }
    }
    catch {
        return [pscustomobject]@{ Task = "$($Task.TaskPath)$($Task.TaskName)"; Status = "falhou"; Error = $_.Exception.Message }
    }
}

function New-Report {
    param(
        [string]$Path,
        [object[]]$Uninstalls,
        [object[]]$Files,
        [object[]]$Tasks,
        [string[]]$Problems,
        [long]$SpaceBefore,
        [long]$SpaceRecovered
    )
    $lines = @()
    $lines += "# Relatorio de limpeza controlada"
    $lines += ""
    $lines += "Gerado em: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
    $lines += ""
    $lines += "## Espaco recuperado"
    $lines += ""
    $lines += "- Bytes recuperados estimados: $SpaceRecovered"
    $lines += "- GB recuperados estimados: {0:N2}" -f ($SpaceRecovered / 1GB)
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
    $lines += "| Arquivo | Status | Tamanho bytes | Motivo | Erro |"
    $lines += "|---|---|---:|---|---|"
    foreach ($f in $Files) {
        $lines += "| $(Escape-Md $f.Path) | $(Escape-Md $f.Status) | $(Escape-Md $f.Bytes) | $(Escape-Md $f.Reason) | $(Escape-Md $f.Error) |"
    }
    $lines += ""
    $lines += "## Tarefas removidas / tentadas"
    $lines += ""
    $lines += "| Tarefa | Status | Erro |"
    $lines += "|---|---|---|"
    foreach ($t in $Tasks) {
        $lines += "| $(Escape-Md $t.Task) | $(Escape-Md $t.Status) | $(Escape-Md $t.Error) |"
    }
    $lines += ""
    $lines += "## Problemas encontrados"
    $lines += ""
    if ($Problems.Count -eq 0) {
        $lines += "- Nenhum problema adicional registrado."
    }
    else {
        foreach ($p in $Problems) { $lines += "- $(Escape-Md $p)" }
    }
    Write-Utf8 $Path $lines
}

$protectedPattern = "(?i)\b(AnyDesk|BRy|SafeNet|Receita|SEFA|SEFAZ|IA-LAB|Docker|WSL|Hyper-V|Ollama|Open WebUI|Python|Conda|Anaconda|Visual Studio Code|VS Code|Git)\b"
$targets = @(
    "TeamViewer",
    "AnyViewer",
    "Advanced SystemCare",
    "iTop Easy Desktop",
    "iTop Data Recovery",
    "iTop Screen Recorder",
    "iTop VPN",
    "Atom",
    "Bizagi Modeler",
    "Mobizen",
    "Microsoft Silverlight",
    "Foxit Reader",
    "Java 8 Update 161",
    "Java 10",
    "MicroStrategy Desktop",
    "VirtualBox"
)

Write-Log "FASE 3 iniciada"
Export-Snapshot $preDir

$prePrograms = Get-InstalledPrograms
$preServices = Get-Service | Select-Object Name, DisplayName, Status, StartType
$preTasks = Get-ScheduledTask -ErrorAction SilentlyContinue | Select-Object TaskName, TaskPath, State

$preLines = @()
$preLines += "# Relatorio pre-remocao"
$preLines += ""
$preLines += "Gerado em: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
$preLines += ""
$preLines += "- Programas instalados exportados: $($prePrograms.Count)"
$preLines += "- Servicos exportados: $($preServices.Count)"
$preLines += "- Tarefas agendadas exportadas: $($preTasks.Count)"
$preLines += "- Pasta snapshot: $preDir"
$preLines += ""
$preLines += "## Alvos solicitados"
foreach ($target in $targets) { $preLines += "- $target" }
$preLines += ""
$preLines += "## Lista de nao tocar respeitada"
$preLines += "- IA-LAB, Docker, WSL, Hyper-V, Ollama, Open WebUI, Python, Conda, VS Code, Git, AnyDesk, BRy, SafeNet, Receita, SEFA."
Write-Utf8 (Join-Path $OutputDir "relatorio_pre_remocao.md") $preLines

$uninstallResults = @()
$problems = New-Object System.Collections.Generic.List[string]
foreach ($target in $targets) {
    $matches = @($prePrograms | Where-Object { $_.DisplayName -like "*$target*" })
    if ($target -eq "Java 10") {
        $matches = @($prePrograms | Where-Object { $_.DisplayName -match "^Java 10|Development Kit 10" })
    }
    if ($target -eq "VirtualBox") {
        $matches = @($prePrograms | Where-Object { $_.DisplayName -match "VirtualBox" })
    }
    if ($matches.Count -eq 0) {
        $uninstallResults += [pscustomobject]@{ Name = $target; Status = "nao encontrado"; Detail = ""; ExitCode = "" }
        continue
    }
    foreach ($program in $matches) {
        if ($program.DisplayName -match $protectedPattern) {
            $uninstallResults += [pscustomobject]@{ Name = $program.DisplayName; Status = "protegido - ignorado"; Detail = "Casou com lista NAO tocar"; ExitCode = "" }
            continue
        }
        $uninstallResults += Invoke-UninstallString $program
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
    $fileResults += Remove-FileControlled $path "arquivo explicitamente solicitado"
}

if (Test-Path $downloads) {
    $installerPatterns = @(
        "VirtualBox-*.exe",
        "TeamViewer*.exe",
        "AnyViewer*.exe",
        "advanced*systemcare*.exe",
        "iTop*.exe",
        "Atom*.exe",
        "Bizagi*.exe",
        "Mobizen*.exe",
        "Silverlight*.exe",
        "Foxit*.exe",
        "MicroStrategy*.exe"
    )
    foreach ($pattern in $installerPatterns) {
        Get-ChildItem -LiteralPath $downloads -Filter $pattern -File -Force -ErrorAction SilentlyContinue |
            ForEach-Object {
                $fileResults += Remove-FileControlled $_.FullName "instalador antigo em Downloads associado aos softwares removidos"
            }
    }
}

$taskResults = @()
$taskPatterns = "TeamViewer|AnyViewer|Advanced SystemCare|IObit|iTop|Atom|Bizagi|Mobizen|Silverlight|Foxit|MicroStrategy|VirtualBox"
$tasks = Get-ScheduledTask -ErrorAction SilentlyContinue |
    Where-Object {
        ($_.TaskName -match $taskPatterns -or $_.TaskPath -match $taskPatterns -or ($_.Actions | Out-String) -match $taskPatterns) -and
        ($_.TaskName -notmatch "AnyDesk|BRy|SafeNet|Receita|SEFA|IA-LAB|Docker|Ollama|Python|Git")
    }
foreach ($task in $tasks) {
    $taskResults += Remove-TaskControlled $task
}

Export-Snapshot $postDir
$spaceRecovered = [long](($fileResults | Where-Object Status -eq "apagado" | Measure-Object Bytes -Sum).Sum)

$postPrograms = Get-InstalledPrograms
$removedPrograms = @()
foreach ($target in $targets) {
    $before = @($prePrograms | Where-Object { $_.DisplayName -like "*$target*" })
    $after = @($postPrograms | Where-Object { $_.DisplayName -like "*$target*" })
    if ($before.Count -gt 0 -and $after.Count -eq 0) { $removedPrograms += $target }
}

New-Report `
    -Path (Join-Path $OutputDir "relatorio_pos_remocao.md") `
    -Uninstalls $uninstallResults `
    -Files $fileResults `
    -Tasks $taskResults `
    -Problems $problems `
    -SpaceBefore 0 `
    -SpaceRecovered $spaceRecovered

Write-Log "FASE 3 concluida. Espaco recuperado estimado: $spaceRecovered bytes"
Write-Output "Relatorios:"
Write-Output (Join-Path $OutputDir "relatorio_pre_remocao.md")
Write-Output (Join-Path $OutputDir "relatorio_pos_remocao.md")
