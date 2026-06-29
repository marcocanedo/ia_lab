param(
    [string]$OutputDir = "C:\inventario_migracao_workstation"
)

$ErrorActionPreference = "Continue"
$ProgressPreference = "SilentlyContinue"

New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null
$now = Get-Date
$userProfile = [Environment]::GetFolderPath("UserProfile")

function Escape-Md {
    param([object]$Value)
    if ($null -eq $Value) { return "" }
    return ([string]$Value).Replace("|", "\|").Replace("`r", " ").Replace("`n", " ").Trim()
}

function Format-Bytes {
    param([double]$Bytes)
    if ($Bytes -le 0) { return "nao calculado" }
    if ($Bytes -ge 1TB) { return "{0:N2} TB" -f ($Bytes / 1TB) }
    if ($Bytes -ge 1GB) { return "{0:N2} GB" -f ($Bytes / 1GB) }
    if ($Bytes -ge 1MB) { return "{0:N2} MB" -f ($Bytes / 1MB) }
    if ($Bytes -ge 1KB) { return "{0:N2} KB" -f ($Bytes / 1KB) }
    return "{0:N0} B" -f $Bytes
}

function Write-Utf8 {
    param([string]$Path, [string[]]$Lines)
    $Lines | Set-Content -Encoding UTF8 -Path $Path
}

function Get-Classification {
    param([string]$Name, [string]$Path, [string]$Kind)
    $text = (($Name + " " + $Path + " " + $Kind).ToLowerInvariant())
    if ($text -match "windows|system32|driver|nvidia|cuda|visual c\+\+|runtime|office|onedrive|ollama|ia-lab|docker|multipass|wsl|python|anaconda|git|vscode|postgres|mysql|redis|sql|security|defender") {
        return "manter"
    }
    if ($text -match "cache|temp|tmp|download|installer|old|backup|logs|node_modules|__pycache__|webex|binance|buds|rstudio|teradata|sped") {
        return "revisar"
    }
    return "revisar"
}

function Get-InstallDateForPathFast {
    param([string]$Path, [object[]]$Apps)
    if (-not $Path) { return "" }
    $match = $Apps |
        Where-Object { $_.InstallLocation -and $Path.StartsWith($_.InstallLocation, [System.StringComparison]::OrdinalIgnoreCase) } |
        Sort-Object { $_.InstallLocation.Length } -Descending |
        Select-Object -First 1
    if ($match -and $match.InstallDate) { return $match.InstallDate }
    return ""
}

function Resolve-CommandPath {
    param([string]$Command)
    if (-not $Command) { return "" }
    $cmd = $Command.Trim()
    if ($cmd -match '^"([^"]+)"') { return $matches[1] }
    if ($cmd -match '^([A-Za-z]:\\[^\s]+)') { return $matches[1] }
    return ""
}

function Get-RunKeyEntries {
    $entries = @()
    $keys = @(
        "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run",
        "HKCU:\Software\Microsoft\Windows\CurrentVersion\RunOnce",
        "HKLM:\Software\Microsoft\Windows\CurrentVersion\Run",
        "HKLM:\Software\Microsoft\Windows\CurrentVersion\RunOnce",
        "HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Run",
        "HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\RunOnce"
    )
    foreach ($key in $keys) {
        $props = Get-ItemProperty -Path $key -ErrorAction SilentlyContinue
        if (-not $props) { continue }
        foreach ($prop in $props.PSObject.Properties) {
            if ($prop.Name -in @("PSPath", "PSParentPath", "PSChildName", "PSDrive", "PSProvider")) { continue }
            $entries += [pscustomobject]@{ Name = $prop.Name; Source = $key; Command = [string]$prop.Value }
        }
    }
    return $entries
}

function Add-ImpactSections {
    param([string[]]$Lines, [object[]]$Rows)
    $Lines += ""
    $Lines += "## A) Ganho de espaco"
    $Lines += ""
    $Lines += "| Item | Tamanho | Classificacao | Observacao |"
    $Lines += "|---|---:|---|---|"
    foreach ($row in ($Rows | Sort-Object TamanhoBytes -Descending | Select-Object -First 20)) {
        $Lines += "| $(Escape-Md $row.Nome) | $(Format-Bytes $row.TamanhoBytes) | $(Escape-Md $row.Classificacao) | Impacto bruto estimado; confirmar antes de remover. |"
    }
    $Lines += ""
    $Lines += "## B) Ganho de memoria RAM"
    $Lines += ""
    $Lines += "| Item | RAM atual | Classificacao | Observacao |"
    $Lines += "|---|---:|---|---|"
    foreach ($row in ($Rows | Sort-Object RamBytes -Descending | Select-Object -First 20)) {
        $Lines += "| $(Escape-Md $row.Nome) | $(Format-Bytes $row.RamBytes) | $(Escape-Md $row.Classificacao) | RAM observada agora; varia por sessao. |"
    }
    $Lines += ""
    $Lines += "## C) Ganho de tempo de boot"
    $Lines += ""
    $Lines += "| Item | Indicador de impacto | Classificacao | Observacao |"
    $Lines += "|---|---:|---|---|"
    foreach ($row in ($Rows | Sort-Object ImpactoBoot -Descending | Select-Object -First 20)) {
        $Lines += "| $(Escape-Md $row.Nome) | $(Format-Bytes $row.ImpactoBoot) | $(Escape-Md $row.Classificacao) | Proxy: RAM atual + tamanho do executavel quando disponivel. |"
    }
    return $Lines
}

$apps = @(
    Get-ItemProperty `
        "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*", `
        "HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*", `
        "HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*" `
        -ErrorAction SilentlyContinue |
        Where-Object DisplayName |
        Select-Object DisplayName, DisplayVersion, InstallDate, InstallLocation
)

$processes = @(Get-Process -ErrorAction SilentlyContinue | Select-Object ProcessName, Id, Path, WorkingSet64, CPU, StartTime)
$processByName = @{}
foreach ($p in $processes) {
    $key = $p.ProcessName.ToLowerInvariant()
    if (-not $processByName.ContainsKey($key)) { $processByName[$key] = @() }
    $processByName[$key] += $p
}

$diskRows = @()
foreach ($app in $apps | Where-Object { $_.InstallLocation -and (Test-Path $_.InstallLocation) }) {
    $item = Get-Item -LiteralPath $app.InstallLocation -Force -ErrorAction SilentlyContinue
    $diskRows += [pscustomobject]@{
        Nome = $app.DisplayName
        Caminho = $app.InstallLocation
        TamanhoBytes = 0
        UltimoUso = if ($item) { $item.LastWriteTime.ToString("yyyy-MM-dd HH:mm") } else { "" }
        Instalacao = $app.InstallDate
        Dependencias = "instalador/registro"
        Classificacao = Get-Classification $app.DisplayName $app.InstallLocation "programa"
        RamBytes = 0
        ImpactoBoot = 0
    }
}

$oneDriveCorp = Get-ChildItem -LiteralPath $userProfile -Directory -Force -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -like "OneDrive - Secretaria da Fazenda*" } |
    Select-Object -First 1 -ExpandProperty FullName

$largeRoots = @(
    (Join-Path $userProfile "Downloads"),
    (Join-Path $userProfile "Documents"),
    (Join-Path $userProfile "Desktop"),
    "C:\IA-LAB"
)
if ($oneDriveCorp) {
    $largeRoots += (Join-Path $oneDriveCorp "backup")
    $largeRoots += $oneDriveCorp
}

foreach ($root in ($largeRoots | Where-Object { Test-Path $_ } | Select-Object -Unique)) {
    Get-ChildItem -LiteralPath $root -File -Force -ErrorAction SilentlyContinue |
        Where-Object { $_.Length -ge 100MB } |
        ForEach-Object {
            $diskRows += [pscustomobject]@{
                Nome = $_.Name
                Caminho = $_.FullName
                TamanhoBytes = $_.Length
                UltimoUso = $_.LastWriteTime.ToString("yyyy-MM-dd HH:mm")
                Instalacao = ""
                Dependencias = "arquivo individual"
                Classificacao = Get-Classification $_.Name $_.FullName "arquivo grande"
                RamBytes = 0
                ImpactoBoot = [double]$_.Length / 100
            }
        }
    Get-ChildItem -LiteralPath $root -Directory -Force -ErrorAction SilentlyContinue |
        Select-Object -First 100 |
        ForEach-Object {
            $approx = 0L
            Get-ChildItem -LiteralPath $_.FullName -File -Force -ErrorAction SilentlyContinue |
                Where-Object { $_.Length -ge 100MB } |
                ForEach-Object { $approx += $_.Length }
            $diskRows += [pscustomobject]@{
                Nome = $_.Name
                Caminho = $_.FullName
                TamanhoBytes = $approx
                UltimoUso = $_.LastWriteTime.ToString("yyyy-MM-dd HH:mm")
                Instalacao = Get-InstallDateForPathFast $_.FullName $apps
                Dependencias = "tamanho estimado por arquivos >=100MB imediatos"
                Classificacao = Get-Classification $_.Name $_.FullName "diretorio"
                RamBytes = 0
                ImpactoBoot = [double]$approx / 100
            }
        }
}
$topDisk = $diskRows | Sort-Object TamanhoBytes -Descending | Select-Object -First 50

$startupRows = @()
foreach ($entry in Get-RunKeyEntries) {
    $cmdPath = Resolve-CommandPath $entry.Command
    $procName = if ($cmdPath) { [System.IO.Path]::GetFileNameWithoutExtension($cmdPath).ToLowerInvariant() } else { $entry.Name.ToLowerInvariant() }
    $procs = if ($processByName.ContainsKey($procName)) { $processByName[$procName] } else { @() }
    $ram = ($procs | Measure-Object WorkingSet64 -Sum).Sum
    $exeSize = if ($cmdPath -and (Test-Path $cmdPath)) { (Get-Item $cmdPath -ErrorAction SilentlyContinue).Length } else { 0 }
    $startupRows += [pscustomobject]@{
        Nome = $entry.Name
        Origem = $entry.Source
        Comando = $entry.Command
        Caminho = $cmdPath
        TamanhoBytes = [double]$exeSize
        RamBytes = [double]$ram
        UltimoUso = if ($cmdPath -and (Test-Path $cmdPath)) { (Get-Item $cmdPath).LastWriteTime.ToString("yyyy-MM-dd HH:mm") } else { "" }
        Instalacao = Get-InstallDateForPathFast $cmdPath $apps
        Dependencias = "Run key"
        Classificacao = Get-Classification $entry.Name $cmdPath "inicializacao"
        ImpactoBoot = [double]$ram + [double]$exeSize
    }
}

$startupFolders = @([Environment]::GetFolderPath("Startup"), "$env:ProgramData\Microsoft\Windows\Start Menu\Programs\Startup")
foreach ($folder in $startupFolders | Where-Object { Test-Path $_ }) {
    Get-ChildItem -LiteralPath $folder -Force -ErrorAction SilentlyContinue | ForEach-Object {
        $startupRows += [pscustomobject]@{
            Nome = $_.Name
            Origem = $folder
            Comando = $_.FullName
            Caminho = $_.FullName
            TamanhoBytes = if ($_.PSIsContainer) { 0 } else { $_.Length }
            RamBytes = 0
            UltimoUso = $_.LastWriteTime.ToString("yyyy-MM-dd HH:mm")
            Instalacao = ""
            Dependencias = "Startup folder"
            Classificacao = Get-Classification $_.Name $_.FullName "startup"
            ImpactoBoot = if ($_.PSIsContainer) { 1 } else { [double]$_.Length }
        }
    }
}

$scheduledTasks = Get-ScheduledTask -ErrorAction SilentlyContinue |
    Where-Object { $_.State -ne "Disabled" -and ($_.Triggers | Where-Object { $_.CimClass.CimClassName -match "Logon|Boot|Startup" }) } |
    Select-Object -First 100
foreach ($task in $scheduledTasks) {
    $actions = @($task.Actions | ForEach-Object { "$($_.Execute) $($_.Arguments)" })
    $ram = 0
    foreach ($p in $processes) {
        if (($actions -join " ") -match [regex]::Escape($p.ProcessName)) { $ram += $p.WorkingSet64 }
    }
    $startupRows += [pscustomobject]@{
        Nome = $task.TaskName
        Origem = "Tarefa agendada $($task.TaskPath)"
        Comando = ($actions -join "; ")
        Caminho = ""
        TamanhoBytes = 0
        RamBytes = [double]$ram
        UltimoUso = ""
        Instalacao = ""
        Dependencias = "Task Scheduler"
        Classificacao = Get-Classification $task.TaskName ($actions -join " ") "tarefa"
        ImpactoBoot = [double]$ram + 1
    }
}
$topStartup = $startupRows | Sort-Object ImpactoBoot -Descending | Select-Object -First 50

$services = Get-Service -ErrorAction SilentlyContinue | Where-Object { $_.Status -eq "Running" -or $_.StartType -eq "Automatic" }
$serviceRows = @()
foreach ($svc in $services) {
    $namePattern = $svc.Name.ToLowerInvariant()
    $procs = @($processes | Where-Object { $_.ProcessName.ToLowerInvariant() -like "*$namePattern*" })
    $ram = ($procs | Measure-Object WorkingSet64 -Sum).Sum
    $serviceRows += [pscustomobject]@{
        Nome = $svc.DisplayName
        Servico = $svc.Name
        Estado = $svc.Status
        StartMode = $svc.StartType
        Caminho = ""
        TamanhoBytes = 0
        RamBytes = [double]$ram
        UltimoUso = ""
        Instalacao = ""
        Dependencias = "Service Control Manager"
        Classificacao = Get-Classification $svc.DisplayName $svc.Name "servico"
        ImpactoBoot = [double]$ram + $(if ($svc.StartType -eq "Automatic") { 1MB } else { 0 })
    }
}
$topServices = $serviceRows | Sort-Object ImpactoBoot -Descending | Select-Object -First 50

$diskLines = @(
    "# Top 50 consumidores de disco",
    "",
    "Gerado em: $($now.ToString('yyyy-MM-dd HH:mm:ss'))",
    "Modo ultra-rapido: arquivos grandes sao medidos diretamente; diretorios usam estimativa por arquivos imediatos >=100MB.",
    "",
    "| # | Item | Caminho | Tamanho ocupado | Ultimo uso | Instalacao | Dependencias detectadas | Classificacao |",
    "|---:|---|---|---:|---|---|---|---|"
)
$i = 1
foreach ($row in $topDisk) {
    $diskLines += "| $i | $(Escape-Md $row.Nome) | $(Escape-Md $row.Caminho) | $(Format-Bytes $row.TamanhoBytes) | $(Escape-Md $row.UltimoUso) | $(Escape-Md $row.Instalacao) | $(Escape-Md $row.Dependencias) | $(Escape-Md $row.Classificacao) |"
    $i++
}
$diskLines = Add-ImpactSections $diskLines $topDisk
Write-Utf8 (Join-Path $OutputDir "top_consumo_disco.md") $diskLines

$startupLines = @(
    "# Top 50 consumidores de inicializacao",
    "",
    "Gerado em: $($now.ToString('yyyy-MM-dd HH:mm:ss'))",
    "Fontes: Run/RunOnce, Startup folders e tarefas agendadas de logon/boot/startup.",
    "",
    "| # | Item | Origem | Comando/caminho | Tamanho ocupado | RAM atual | Ultimo uso | Instalacao | Dependencias detectadas | Classificacao |",
    "|---:|---|---|---|---:|---:|---|---|---|---|"
)
$i = 1
foreach ($row in $topStartup) {
    $startupLines += "| $i | $(Escape-Md $row.Nome) | $(Escape-Md $row.Origem) | $(Escape-Md $row.Comando) | $(Format-Bytes $row.TamanhoBytes) | $(Format-Bytes $row.RamBytes) | $(Escape-Md $row.UltimoUso) | $(Escape-Md $row.Instalacao) | $(Escape-Md $row.Dependencias) | $(Escape-Md $row.Classificacao) |"
    $i++
}
$startupLines = Add-ImpactSections $startupLines $topStartup
Write-Utf8 (Join-Path $OutputDir "top_inicializacao.md") $startupLines

$serviceLines = @(
    "# Top 50 servicos por impacto estimado",
    "",
    "Gerado em: $($now.ToString('yyyy-MM-dd HH:mm:ss'))",
    "Fontes: Get-Service e processos atuais. RAM pode ficar vazia quando o servico compartilha svchost.",
    "",
    "| # | Servico | Nome interno | Estado | StartMode | Tamanho ocupado | RAM atual | Ultimo uso | Instalacao | Dependencias detectadas | Classificacao |",
    "|---:|---|---|---|---|---:|---:|---|---|---|---|"
)
$i = 1
foreach ($row in $topServices) {
    $serviceLines += "| $i | $(Escape-Md $row.Nome) | $(Escape-Md $row.Servico) | $(Escape-Md $row.Estado) | $(Escape-Md $row.StartMode) | $(Format-Bytes $row.TamanhoBytes) | $(Format-Bytes $row.RamBytes) | $(Escape-Md $row.UltimoUso) | $(Escape-Md $row.Instalacao) | $(Escape-Md $row.Dependencias) | $(Escape-Md $row.Classificacao) |"
    $i++
}
$serviceLines = Add-ImpactSections $serviceLines $topServices
Write-Utf8 (Join-Path $OutputDir "top_servicos.md") $serviceLines

Write-Output "Relatorios gerados:"
Write-Output (Join-Path $OutputDir "top_consumo_disco.md")
Write-Output (Join-Path $OutputDir "top_inicializacao.md")
Write-Output (Join-Path $OutputDir "top_servicos.md")
