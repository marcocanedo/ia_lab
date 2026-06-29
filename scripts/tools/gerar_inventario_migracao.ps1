param(
    [string]$OutputDir = "C:\inventario_migracao_workstation"
)

$ErrorActionPreference = "Continue"
$ProgressPreference = "SilentlyContinue"

$now = Get-Date
$userProfile = [Environment]::GetFolderPath("UserProfile")
$computer = $env:COMPUTERNAME

New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null

function Escape-Md {
    param([object]$Value)
    if ($null -eq $Value) { return "" }
    return ([string]$Value).Replace("|", "\|").Replace("`r", " ").Replace("`n", " ").Trim()
}

function Write-Utf8 {
    param([string]$Path, [string[]]$Lines)
    $Lines | Set-Content -Encoding UTF8 -Path $Path
}

function Invoke-Capture {
    param([string]$Name, [scriptblock]$Script)
    try {
        $output = & $Script 2>&1
        [pscustomobject]@{
            name = $Name
            ok = $true
            output = ($output | Out-String).Trim()
        }
    }
    catch {
        [pscustomobject]@{
            name = $Name
            ok = $false
            output = $_.Exception.Message
        }
    }
}

function Get-Recommendation {
    param([string]$Name, [string]$Category, [bool]$InProcess, [bool]$InService)
    $n = $Name.ToLowerInvariant()
    if ($Category -in @("sistema", "desenvolvimento", "IA/LLM", "banco de dados")) { return "manter" }
    if ($InProcess -or $InService) { return "manter" }
    if ($n -match "driver|nvidia|cuda|runtime|redistributable|visual c\+\+|windows|security|update|edge|teams|office|onedrive") { return "nao mexer" }
    if ($Category -eq "desconhecido") { return "avaliar" }
    return "avaliar"
}

function Get-Category {
    param([string]$Name)
    $n = $Name.ToLowerInvariant()
    if ($n -match "ollama|open webui|lm studio|cuda|nvidia|torch|tensorflow|hugging|llama|stable diffusion|comfyui|webui") { return "IA/LLM" }
    if ($n -match "python|git|docker|visual studio code|vscode|node|npm|java|jdk|wsl|powershell|cmake|gcc|mingw|streamlit|postman|anaconda|conda") { return "desenvolvimento" }
    if ($n -match "postgres|mysql|mariadb|sql server|sqlite|redis|mongodb|dbeaver|pgadmin") { return "banco de dados" }
    if ($n -match "driver|windows|microsoft|office|edge|teams|onedrive|security|defender|runtime|redistributable|update") { return "sistema" }
    if ($n -match "7-zip|notepad|winrar|pdf|chrome|firefox|vpn|zoom|anydesk") { return "utilitario" }
    return "desconhecido"
}

function Get-FolderSizeApprox {
    param([string]$Path)
    try {
        $skip = "\\(node_modules|\.venv|venv|env|__pycache__|\.git|\.mypy_cache|\.pytest_cache|cache|models|blobs)(\\|$)"
        $sum = 0L
        Get-ChildItem -LiteralPath $Path -File -Recurse -Force -ErrorAction SilentlyContinue |
            Where-Object { $_.FullName -notmatch $skip } |
            ForEach-Object { $sum += $_.Length }
        if ($sum -ge 1GB) { return "{0:N2} GB" -f ($sum / 1GB) }
        if ($sum -ge 1MB) { return "{0:N2} MB" -f ($sum / 1MB) }
        if ($sum -ge 1KB) { return "{0:N2} KB" -f ($sum / 1KB) }
        return "$sum B"
    }
    catch {
        return "indisponivel"
    }
}

function Get-LastWriteRecursive {
    param([string]$Path)
    try {
        $latest = Get-ChildItem -LiteralPath $Path -Recurse -Force -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTime -Descending |
            Select-Object -First 1
        if ($latest) { return $latest.LastWriteTime.ToString("yyyy-MM-dd HH:mm") }
        return (Get-Item -LiteralPath $Path -Force).LastWriteTime.ToString("yyyy-MM-dd HH:mm")
    }
    catch {
        return ""
    }
}

function Test-HasGit {
    param([string]$Path)
    return (Test-Path -LiteralPath (Join-Path $Path ".git"))
}

function Get-DependencyMarkers {
    param([string]$Path)
    $markers = @(
        "requirements.txt", "pyproject.toml", "environment.yml", "environment.yaml",
        "Pipfile", "poetry.lock", "package.json", "docker-compose.yml",
        "Dockerfile", "Cargo.toml", "pom.xml", "build.gradle", "*.sln"
    )
    $found = New-Object System.Collections.Generic.List[string]
    foreach ($marker in $markers) {
        $items = Get-ChildItem -LiteralPath $Path -Filter $marker -File -Force -ErrorAction SilentlyContinue
        foreach ($item in $items) { $found.Add($item.Name) }
    }
    return (($found | Select-Object -Unique) -join ", ")
}

function Get-ProjectType {
    param([string]$Path)
    $files = @(Get-ChildItem -LiteralPath $Path -File -Force -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Name)
    $allNames = ($files -join " ").ToLowerInvariant()
    if ($files -contains "docker-compose.yml") { return "Docker/Open WebUI/servico" }
    if ($files -contains "pyproject.toml" -or $files -contains "requirements.txt" -or $allNames -match "\.py") { return "Python" }
    if ($files -contains "package.json") { return "Node/JavaScript" }
    if ($allNames -match "\.ipynb") { return "Notebooks" }
    if ($allNames -match "\.sql") { return "SQL/banco" }
    if ($allNames -match "\.ps1") { return "PowerShell/automacao" }
    if (Test-HasGit $Path) { return "Repositorio Git" }
    return "Tecnico/misto"
}

function Get-BackupRecommendation {
    param([string]$Path, [string]$Type)
    $p = $Path.ToLowerInvariant()
    if ($p -match "ia-lab|receita|daaf|saif|malha|auditoria|ollama|webui|streamlit|python|sql") { return "obrigatorio" }
    if ($Type -in @("Python", "Repositorio Git", "SQL/banco", "PowerShell/automacao", "Docker/Open WebUI/servico")) { return "recomendado" }
    return "verificar"
}

function Find-ProjectCandidates {
    param([string[]]$Roots)
    $exclude = @("node_modules", ".venv", "venv", "env", "__pycache__", ".git", ".mypy_cache", ".pytest_cache", "AppData", "Windows", "Program Files", "Program Files (x86)", "ProgramData")
    $candidateMap = @{}
    foreach ($root in ($Roots | Where-Object { $_ -and (Test-Path -LiteralPath $_) } | Select-Object -Unique)) {
        $queue = New-Object System.Collections.Queue
        $queue.Enqueue([pscustomobject]@{ path = (Resolve-Path $root).Path; depth = 0 })
        while ($queue.Count -gt 0) {
            $entry = $queue.Dequeue()
            $path = $entry.path
            $depth = [int]$entry.depth
            if ($depth -gt 6) { continue }
            $leaf = Split-Path -Leaf $path
            if ($exclude -contains $leaf) { continue }

            $files = @(Get-ChildItem -LiteralPath $path -File -Force -ErrorAction SilentlyContinue)
            $names = ($files | Select-Object -ExpandProperty Name)
            $hasMarker = (
                (Test-Path -LiteralPath (Join-Path $path ".git")) -or
                ($names -contains "requirements.txt") -or
                ($names -contains "pyproject.toml") -or
                ($names -contains "environment.yml") -or
                ($names -contains "environment.yaml") -or
                ($names -contains "package.json") -or
                ($names -contains "docker-compose.yml") -or
                ($names -contains "Dockerfile") -or
                (($files | Where-Object { $_.Extension -in @(".ipynb", ".py", ".sql", ".ps1", ".md") }).Count -ge 2)
            )
            $nameLooksImportant = ($path -match "(?i)ia|llm|ollama|webui|streamlit|receita|daaf|saif|malha|auditoria|python|sql|scripts|notebook|repo|project|source|ssh|codex|vscode|docker|kube|aws|azure")
            if ($hasMarker -or ($nameLooksImportant -and $files.Count -gt 0)) {
                $candidateMap[$path] = $true
            }

            if ($depth -lt 6) {
                Get-ChildItem -LiteralPath $path -Directory -Force -ErrorAction SilentlyContinue |
                    Where-Object { $exclude -notcontains $_.Name } |
                    ForEach-Object { $queue.Enqueue([pscustomobject]@{ path = $_.FullName; depth = $depth + 1 }) }
            }
        }
    }
    return $candidateMap.Keys | Sort-Object
}

$processes = @(Get-Process -ErrorAction SilentlyContinue | Select-Object ProcessName, Id, Path, StartTime)
$serviceRows = @(Get-Service -ErrorAction SilentlyContinue | Select-Object Name, DisplayName, Status, StartType)
$processNames = @{}
foreach ($p in $processes) { $processNames[$p.ProcessName.ToLowerInvariant()] = $true }

$captures = [ordered]@{}
$captures["winget"] = Invoke-Capture "winget list" { winget list }
$captures["choco"] = Invoke-Capture "choco list" { if (Get-Command choco -ErrorAction SilentlyContinue) { choco list --local-only } else { "Chocolatey nao encontrado" } }
$captures["scoop"] = Invoke-Capture "scoop list" { if (Get-Command scoop -ErrorAction SilentlyContinue) { scoop list } else { "Scoop nao encontrado" } }
$captures["pip"] = Invoke-Capture "python pip list" { if (Get-Command python -ErrorAction SilentlyContinue) { python -m pip list } else { "python nao encontrado no PATH" } }
$captures["py_pip"] = Invoke-Capture "py pip list" { if (Get-Command py -ErrorAction SilentlyContinue) { py -m pip list } else { "py launcher nao encontrado" } }
$captures["conda"] = Invoke-Capture "conda env list" { if (Get-Command conda -ErrorAction SilentlyContinue) { conda env list } else { "Conda nao encontrado no PATH" } }
$captures["vscode_extensions"] = Invoke-Capture "code extensions" { if (Get-Command code -ErrorAction SilentlyContinue) { code --list-extensions --show-versions } else { "code CLI nao encontrado" } }
$captures["wsl"] = Invoke-Capture "wsl list" { if (Get-Command wsl -ErrorAction SilentlyContinue) { wsl -l -v } else { "WSL nao encontrado" } }
$captures["docker"] = Invoke-Capture "docker ps" { if (Get-Command docker -ErrorAction SilentlyContinue) { docker ps -a } else { "Docker CLI nao encontrado no PATH" } }
$captures["ollama"] = Invoke-Capture "ollama list" { if (Get-Command ollama -ErrorAction SilentlyContinue) { $env:OLLAMA_HOST = "127.0.0.1:11436"; ollama list } else { "Ollama nao encontrado" } }
$captures["scheduled_tasks"] = Invoke-Capture "tarefas agendadas IA/dev" {
    Get-ScheduledTask -ErrorAction SilentlyContinue |
        Where-Object { $_.TaskName -match "IA|LAB|Ollama|Open|Python|Backup|PX|Docker|WSL|Streamlit" -or $_.TaskPath -match "IA|LAB|Ollama|Open|Python|Backup|PX|Docker|WSL|Streamlit" } |
        Select-Object TaskName, TaskPath, State | Format-Table -AutoSize
}
$captures["ports"] = Invoke-Capture "portas locais" { netstat -ano | Select-String "LISTENING|ESTABLISHED" }
$captures["env"] = Invoke-Capture "variaveis relevantes" {
    Get-ChildItem Env: |
        Where-Object { $_.Name -match "OLLAMA|OPENAI|HTTP|HTTPS|PROXY|PYTHON|CONDA|CUDA|DOCKER|WSL|JAVA|PATH|IA|LAB|STREAMLIT" } |
        Sort-Object Name | Format-Table -AutoSize
}

$registryApps = @()
$uninstallRoots = @(
    "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*",
    "HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*",
    "HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*"
)
foreach ($root in $uninstallRoots) {
    $registryApps += Get-ItemProperty $root -ErrorAction SilentlyContinue |
        Where-Object { $_.DisplayName } |
        Select-Object DisplayName, DisplayVersion, Publisher, InstallDate, InstallLocation
}
$registryApps = $registryApps | Sort-Object DisplayName -Unique

$programRows = @()
foreach ($app in $registryApps) {
    $cat = Get-Category $app.DisplayName
    $nameLower = $app.DisplayName.ToLowerInvariant()
    $inProc = $false
    foreach ($pn in $processNames.Keys) {
        if ($nameLower -match [regex]::Escape($pn)) { $inProc = $true; break }
    }
    $svc = @($serviceRows | Where-Object { $_.DisplayName -like "*$($app.DisplayName)*" -or $app.DisplayName -like "*$($_.DisplayName)*" } | Select-Object -First 1)
    $inSvc = $svc.Count -gt 0
    $evidence = @()
    if ($inProc) { $evidence += "processo atual" }
    if ($inSvc) { $evidence += "servico cadastrado" }
    if ($app.InstallDate) { $evidence += "InstallDate=$($app.InstallDate)" }
    if ($app.InstallLocation) {
        try {
            $loc = Get-Item -LiteralPath $app.InstallLocation -ErrorAction SilentlyContinue
            if ($loc) { $evidence += "pasta modificada=$($loc.LastWriteTime.ToString('yyyy-MM-dd'))" }
        } catch {}
    }
    $rec = Get-Recommendation $app.DisplayName $cat $inProc $inSvc
    $programRows += [pscustomobject]@{
        Nome = $app.DisplayName
        Versao = $app.DisplayVersion
        Origem = "Registro Windows"
        Categoria = $cat
        Uso = ($evidence -join "; ")
        Recomendacao = $rec
        Justificativa = if ($rec -eq "manter") { "Componente relevante ou com indicio de uso." } elseif ($rec -eq "nao mexer") { "Componente de sistema/runtime/driver; remover pode quebrar dependencias." } else { "Sem evidencia suficiente; verificar manualmente antes de qualquer remocao." }
    }
}

$serviceImportant = $serviceRows | Where-Object {
    $_.DisplayName -match "Ollama|Open|Docker|Postgre|MySQL|Redis|SQL|NVIDIA|CUDA|WSL|Python|Streamlit|IA|LAB|SSH"
}

$roots = New-Object System.Collections.Generic.List[string]
foreach ($p in @(
    (Join-Path $userProfile "Desktop"),
    (Join-Path $userProfile "Documents"),
    (Join-Path $userProfile "Downloads"),
    (Join-Path $userProfile "OneDrive"),
    (Join-Path $userProfile "source"),
    (Join-Path $userProfile "projects"),
    (Join-Path $userProfile "repos"),
    (Join-Path $userProfile ".ssh"),
    (Join-Path $userProfile ".codex"),
    (Join-Path $userProfile ".vscode"),
    (Join-Path $userProfile ".ollama"),
    (Join-Path $userProfile ".docker"),
    (Join-Path $userProfile ".kube"),
    (Join-Path $userProfile ".aws"),
    (Join-Path $userProfile ".azure"),
    "C:\IA-LAB"
)) {
    if (Test-Path -LiteralPath $p) { $roots.Add($p) }
}
Get-ChildItem -LiteralPath $userProfile -Directory -Force -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -match "(?i)OneDrive|source|project|repo|ia|python|sql|notebook" } |
    ForEach-Object { $roots.Add($_.FullName) }
Get-ChildItem -LiteralPath "C:\" -Directory -Force -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -match "(?i)IA|LAB|Python|SQL|Ollama|Open|WebUI|Streamlit|Receita|DAAF|SAIF|Malha|Auditoria|Projet|Repo|Source" } |
    ForEach-Object { $roots.Add($_.FullName) }

$projectPaths = Find-ProjectCandidates -Roots ($roots | Select-Object -Unique)
$projectRows = @()
$sensitiveRows = @()
$largeRows = @()

$sensitivePatterns = @(".env", "*.pem", "*.key", "id_rsa", "id_ed25519", "*.pfx", "*.p12", "*.crt", "*token*", "*senha*", "*password*", "*secret*", "*.kdbx")
$dbPatterns = @("*.bak", "*.dump", "*.sql", "*.sqlite", "*.sqlite3", "*.db", "*.parquet", "*.csv", "*.xlsx")

foreach ($path in $projectPaths) {
    $type = Get-ProjectType $path
    $deps = Get-DependencyMarkers $path
    $sens = New-Object System.Collections.Generic.List[string]
    foreach ($pattern in $sensitivePatterns) {
        Get-ChildItem -LiteralPath $path -Filter $pattern -File -Recurse -Force -ErrorAction SilentlyContinue |
            Where-Object { $_.FullName -notmatch "\\(node_modules|\.venv|venv|__pycache__|\.git)\\" } |
            Select-Object -First 10 |
            ForEach-Object {
                $sens.Add($_.FullName)
                $sensitiveRows += [pscustomobject]@{
                    Caminho = $_.FullName
                    Tipo = "possivel segredo/config sensivel"
                    Tamanho = $_.Length
                    UltimaModificacao = $_.LastWriteTime.ToString("yyyy-MM-dd HH:mm")
                    Cuidado = "Nao copiar para ambientes compartilhados sem avaliar conteudo e permissao."
                }
            }
    }
    foreach ($pattern in $dbPatterns) {
        Get-ChildItem -LiteralPath $path -Filter $pattern -File -Recurse -Force -ErrorAction SilentlyContinue |
            Where-Object { $_.FullName -notmatch "\\(node_modules|\.venv|venv|__pycache__|\.git)\\" } |
            Select-Object -First 20 |
            ForEach-Object {
                $sensitiveRows += [pscustomobject]@{
                    Caminho = $_.FullName
                    Tipo = "base/dump/dado possivelmente sensivel"
                    Tamanho = $_.Length
                    UltimaModificacao = $_.LastWriteTime.ToString("yyyy-MM-dd HH:mm")
                    Cuidado = "Pode conter dados pessoais/fiscais; proteger no backup."
                }
            }
    }

    Get-ChildItem -LiteralPath $path -File -Recurse -Force -ErrorAction SilentlyContinue |
        Where-Object { $_.Length -ge 500MB -and $_.FullName -notmatch "\\(node_modules|\.venv|venv|__pycache__|\.git)\\" } |
        Select-Object -First 20 |
        ForEach-Object {
            $largeRows += [pscustomobject]@{
                Caminho = $_.FullName
                Tamanho = "{0:N2} GB" -f ($_.Length / 1GB)
                UltimaModificacao = $_.LastWriteTime.ToString("yyyy-MM-dd HH:mm")
                Cuidado = "Arquivo grande; verificar necessidade, duplicidade e local de backup."
            }
        }

    $projectRows += [pscustomobject]@{
        Caminho = $path
        Tipo = $type
        Ferramenta = if ($type -eq "Python") { "Python" } elseif ($type -eq "SQL/banco") { "SQL" } elseif ($type -eq "PowerShell/automacao") { "PowerShell" } else { $type }
        Tamanho = Get-FolderSizeApprox $path
        UltimaModificacao = Get-LastWriteRecursive $path
        Git = if (Test-HasGit $path) { "sim" } else { "nao" }
        Dependencias = $deps
        Sensiveis = if ($sens.Count -gt 0) { "sim ($($sens.Count))" } else { "nao detectado" }
        Backup = Get-BackupRecommendation $path $type
    }
}

$recentFiles = @()
foreach ($root in ($roots | Select-Object -Unique)) {
    $recentFiles += Get-ChildItem -LiteralPath $root -File -Recurse -Force -ErrorAction SilentlyContinue |
        Where-Object {
            $_.FullName -notmatch "\\(node_modules|\.venv|venv|__pycache__|\.git|cache|models|blobs)\\" -and
            $_.Extension -in @(".py", ".ps1", ".sql", ".ipynb", ".md", ".yaml", ".yml", ".json", ".toml", ".docx", ".pdf")
        } |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 100 FullName, Extension, Length, LastWriteTime
}
$recentFiles = $recentFiles | Sort-Object LastWriteTime -Descending | Select-Object -First 100

$auxScripts = @{
    "01_coletar_inventario.ps1" = @'
$ErrorActionPreference = "Continue"
Write-Output "Somente leitura: inventario basico de programas, servicos, processos e portas."
winget list
Get-ItemProperty HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*,HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*,HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\* -ErrorAction SilentlyContinue | Where-Object DisplayName | Select-Object DisplayName,DisplayVersion,Publisher,InstallDate,InstallLocation
Get-Service | Sort-Object DisplayName
Get-Process | Select-Object ProcessName,Id,Path,StartTime
netstat -ano
'@
    "02_mapear_projetos.ps1" = @'
$ErrorActionPreference = "Continue"
Write-Output "Somente leitura: busca projetos e arquivos tecnicos em locais provaveis."
$roots = @("$env:USERPROFILE\Desktop","$env:USERPROFILE\Documents","$env:USERPROFILE\Downloads","$env:USERPROFILE\OneDrive","$env:USERPROFILE\source","$env:USERPROFILE\projects","$env:USERPROFILE\repos","C:\IA-LAB") | Where-Object { Test-Path -LiteralPath $_ }
foreach ($root in $roots) {
    Get-ChildItem -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match '(^\.git$|requirements\.txt|pyproject\.toml|environment\.ya?ml|package\.json|docker-compose\.yml|\.ipynb$|\.py$|\.sql$|\.ps1$|\.md$)' } |
        Select-Object FullName,Length,LastWriteTime
}
'@
    "03_gerar_plano_backup.ps1" = @'
$ErrorActionPreference = "Continue"
Write-Output "Somente leitura: use os relatorios gerados para montar plano de backup. Este script nao copia arquivos."
Write-Output "Revise C:\inventario_migracao_workstation\plano_backup.md"
'@
    "04_listar_candidatos_desinstalacao.ps1" = @'
$ErrorActionPreference = "Continue"
Write-Output "Somente leitura: lista instalados para avaliacao manual. Nao desinstala."
winget list
'@
}
foreach ($name in $auxScripts.Keys) {
    Write-Utf8 (Join-Path $OutputDir $name) ($auxScripts[$name] -split "`n")
}

$programLines = @()
$programLines += "# Inventario de programas"
$programLines += ""
$programLines += "Gerado em: $($now.ToString('yyyy-MM-dd HH:mm:ss'))"
$programLines += "Maquina: $computer"
$programLines += ""
$programLines += "## Tabela consolidada do Registro Windows"
$programLines += ""
$programLines += "| Nome | Versao | Origem provavel | Categoria | Evidencia de uso recente | Recomendacao | Justificativa |"
$programLines += "|---|---:|---|---|---|---|---|"
foreach ($row in ($programRows | Sort-Object Nome)) {
    $programLines += "| $(Escape-Md $row.Nome) | $(Escape-Md $row.Versao) | $(Escape-Md $row.Origem) | $(Escape-Md $row.Categoria) | $(Escape-Md $row.Uso) | $(Escape-Md $row.Recomendacao) | $(Escape-Md $row.Justificativa) |"
}
$programLines += ""
$programLines += "## Saidas brutas complementares"
foreach ($cap in $captures.Values) {
    $programLines += ""
    $programLines += "### $($cap.name)"
    $programLines += ""
    $programLines += '```text'
    $programLines += if ($cap.output) { $cap.output } else { "(sem saida)" }
    $programLines += '```'
}
$programLines += ""
$programLines += "## Servicos relevantes"
$programLines += ""
$programLines += "| Nome | DisplayName | Status | StartType |"
$programLines += "|---|---|---|---|"
foreach ($svc in ($serviceImportant | Sort-Object DisplayName)) {
    $programLines += "| $(Escape-Md $svc.Name) | $(Escape-Md $svc.DisplayName) | $(Escape-Md $svc.Status) | $(Escape-Md $svc.StartType) |"
}
Write-Utf8 (Join-Path $OutputDir "inventario_programas.md") $programLines

$projectLines = @()
$projectLines += "# Inventario de projetos, scripts e repositorios"
$projectLines += ""
$projectLines += "Gerado em: $($now.ToString('yyyy-MM-dd HH:mm:ss'))"
$projectLines += ""
$projectLines += "## Projetos encontrados"
$projectLines += ""
$projectLines += "| Caminho completo | Tipo | Linguagem/ferramenta | Tamanho aprox. | Ultima modificacao | Git | Dependencias detectadas | Sensiveis possiveis | Backup |"
$projectLines += "|---|---|---|---:|---|---|---|---|---|"
foreach ($row in ($projectRows | Sort-Object Backup, Caminho)) {
    $projectLines += "| $(Escape-Md $row.Caminho) | $(Escape-Md $row.Tipo) | $(Escape-Md $row.Ferramenta) | $(Escape-Md $row.Tamanho) | $(Escape-Md $row.UltimaModificacao) | $(Escape-Md $row.Git) | $(Escape-Md $row.Dependencias) | $(Escape-Md $row.Sensiveis) | $(Escape-Md $row.Backup) |"
}
$projectLines += ""
$projectLines += "## Arquivos tecnicos recentes"
$projectLines += ""
$projectLines += "| Caminho | Extensao | Tamanho | Ultima modificacao |"
$projectLines += "|---|---|---:|---|"
foreach ($f in $recentFiles) {
    $projectLines += "| $(Escape-Md $f.FullName) | $(Escape-Md $f.Extension) | $(Escape-Md $f.Length) | $(Escape-Md $f.LastWriteTime.ToString('yyyy-MM-dd HH:mm')) |"
}
Write-Utf8 (Join-Path $OutputDir "inventario_projetos.md") $projectLines

$essential = $projectRows | Where-Object Backup -eq "obrigatorio" | Sort-Object Caminho
$important = $projectRows | Where-Object Backup -eq "recomendado" | Sort-Object Caminho
$optional = $projectRows | Where-Object Backup -eq "opcional" | Sort-Object Caminho
$verify = $projectRows | Where-Object Backup -eq "verificar" | Sort-Object Caminho

$backupLines = @()
$backupLines += "# Plano de backup"
$backupLines += ""
$backupLines += "Principio: copiar projetos e configuracoes, evitando caches e dependencias regeneraveis quando possivel."
$backupLines += ""
$backupSections = @(
    [pscustomobject]@{ title = "Essencial"; rows = $essential },
    [pscustomobject]@{ title = "Importante"; rows = $important },
    [pscustomobject]@{ title = "Opcional"; rows = $optional },
    [pscustomobject]@{ title = "Verificar manualmente"; rows = $verify }
)
foreach ($section in $backupSections) {
    $backupLines += "## $($section.title)"
    $backupLines += ""
    if (@($section.rows).Count -eq 0) {
        $backupLines += "- Nenhum item classificado nesta categoria."
    }
    else {
        foreach ($row in $section.rows) {
            $backupLines += "- $($row.Caminho) - $($row.Tipo), ultima modificacao $($row.UltimaModificacao), dependencias: $($row.Dependencias)"
        }
    }
    $backupLines += ""
}
$backupLines += "## Excluir ou tratar com cuidado durante copia"
$backupLines += ""
$backupLines += '- `node_modules`, `.venv`, `venv`, `__pycache__`, `.mypy_cache`, `.pytest_cache`: normalmente regeneraveis.'
$backupLines += "- Caches de modelos e blobs do Ollama/Open WebUI: podem ser muito grandes; copiar somente se a nova maquina precisar evitar novo download."
$backupLines += "- Dumps e bases fiscais/pessoais: copiar com criptografia e controle de acesso."
Write-Utf8 (Join-Path $OutputDir "plano_backup.md") $backupLines

$uninstallCandidates = $programRows | Where-Object {
    $_.Recomendacao -eq "avaliar" -and $_.Categoria -in @("utilitario", "desconhecido") -and -not $_.Uso
} | Sort-Object Nome
$uninstallLines = @()
$uninstallLines += "# Candidatos a desinstalacao futura"
$uninstallLines += ""
$uninstallLines += "Nenhum item deve ser removido automaticamente. Esta lista e apenas triagem para revisao manual."
$uninstallLines += ""
$uninstallLines += "| Nome | Versao | Categoria | Motivo | Risco de remocao |"
$uninstallLines += "|---|---:|---|---|---|"
foreach ($row in $uninstallCandidates) {
    $uninstallLines += "| $(Escape-Md $row.Nome) | $(Escape-Md $row.Versao) | $(Escape-Md $row.Categoria) | Sem evidencia de processo/servico ou uso recente no inventario automatico. | Pode ser dependencia indireta ou ferramenta usada raramente; confirmar com usuario antes. |"
}
Write-Utf8 (Join-Path $OutputDir "candidatos_desinstalacao.md") $uninstallLines

$riskLines = @()
$riskLines += "# Riscos e arquivos sensiveis"
$riskLines += ""
$riskLines += "Nao abrir ou transferir estes arquivos sem avaliar permissao, destino e protecao do backup."
$riskLines += ""
$riskLines += "## Possiveis segredos, chaves, tokens e configuracoes sensiveis"
$riskLines += ""
$riskLines += "| Caminho | Tipo | Tamanho | Ultima modificacao | Cuidado |"
$riskLines += "|---|---|---:|---|---|"
foreach ($row in ($sensitiveRows | Sort-Object Caminho -Unique)) {
    $riskLines += "| $(Escape-Md $row.Caminho) | $(Escape-Md $row.Tipo) | $(Escape-Md $row.Tamanho) | $(Escape-Md $row.UltimaModificacao) | $(Escape-Md $row.Cuidado) |"
}
$riskLines += ""
$riskLines += "## Arquivos grandes"
$riskLines += ""
$riskLines += "| Caminho | Tamanho | Ultima modificacao | Cuidado |"
$riskLines += "|---|---:|---|---|"
foreach ($row in ($largeRows | Sort-Object Caminho -Unique)) {
    $riskLines += "| $(Escape-Md $row.Caminho) | $(Escape-Md $row.Tamanho) | $(Escape-Md $row.UltimaModificacao) | $(Escape-Md $row.Cuidado) |"
}
Write-Utf8 (Join-Path $OutputDir "riscos_e_arquivos_sensiveis.md") $riskLines

$summaryLines = @()
$summaryLines += "# Resumo executivo"
$summaryLines += ""
$summaryLines += "Gerado em: $($now.ToString('yyyy-MM-dd HH:mm:ss'))"
$summaryLines += ""
$summaryLines += "## O que parece realmente usado"
$summaryLines += ""
$usedPrograms = $programRows | Where-Object { $_.Uso -or $_.Categoria -in @("IA/LLM", "desenvolvimento", "banco de dados") } | Select-Object -First 30
foreach ($row in $usedPrograms) {
    $summaryLines += "- $($row.Nome) - $($row.Categoria) - $($row.Uso)"
}
$summaryLines += ""
$summaryLines += "## O que parece legado ou exige avaliacao"
$summaryLines += ""
foreach ($row in ($uninstallCandidates | Select-Object -First 30)) {
    $summaryLines += "- $($row.Nome) - verificar manualmente antes de remover."
}
$summaryLines += ""
$summaryLines += "## Backup urgente"
$summaryLines += ""
foreach ($row in ($essential | Select-Object -First 40)) {
    $summaryLines += "- $($row.Caminho)"
}
$summaryLines += ""
$summaryLines += "## Revisar manualmente"
$summaryLines += ""
$summaryLines += '- Arquivos listados em `riscos_e_arquivos_sensiveis.md`.'
$summaryLines += "- Projetos sem Git ou sem manifestos claros."
$summaryLines += '- Programas classificados como `avaliar`.'
$summaryLines += "- Caches de modelos e bases grandes antes de copiar para a nova workstation."
$summaryLines += ""
$summaryLines += "## Proximos passos sugeridos"
$summaryLines += ""
$summaryLines += '1. Revisar `plano_backup.md` e confirmar destinos de backup.'
$summaryLines += "2. Separar segredos/chaves em backup protegido."
$summaryLines += "3. Exportar listas de ambientes Python/Conda e extensoes VS Code."
$summaryLines += "4. Confirmar se modelos Ollama/Open WebUI serao copiados ou baixados novamente."
$summaryLines += '5. Somente depois do backup validado, revisar `candidatos_desinstalacao.md`.'
Write-Utf8 (Join-Path $OutputDir "resumo_executivo.md") $summaryLines

$metadata = [pscustomobject]@{
    generated_at = $now.ToString("s")
    computer = $computer
    output_dir = $OutputDir
    program_count = @($programRows).Count
    project_count = @($projectRows).Count
    sensitive_count = @($sensitiveRows).Count
    large_file_count = @($largeRows).Count
}
$metadata | ConvertTo-Json -Depth 5 | Set-Content -Encoding UTF8 -Path (Join-Path $OutputDir "metadata.json")

Write-Output "Relatorios gerados em: $OutputDir"
Write-Output "Programas: $($metadata.program_count)"
Write-Output "Projetos: $($metadata.project_count)"
Write-Output "Riscos/sensiveis: $($metadata.sensitive_count)"
Write-Output "Arquivos grandes: $($metadata.large_file_count)"
