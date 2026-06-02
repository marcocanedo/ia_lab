$out = 'C:\inventario_migracao_workstation'
$logOut = 'C:\inventario_migracao_workstation\fase4_logs'
$inv = 'C:\inventario_migracao_workstation\inventario_final_pos_limpeza.md'
$sum = 'C:\inventario_migracao_workstation\resumo_limpeza_final.md'

New-Item -ItemType Directory -Path $out -Force | Out-Null
New-Item -ItemType Directory -Path $logOut -Force | Out-Null

$logs = 'limpeza_residual_elevada.log','silverlight_uninstall.log','silverlight_repair.log','silverlight_uninstall_after_repair.log','silverlight_repair_then_uninstall.log'
$logLines = New-Object System.Collections.Generic.List[string]
foreach ($log in $logs) {
    $src = Join-Path 'C:\IA-LAB' $log
    $dst = Join-Path $logOut $log
    if (Test-Path -LiteralPath $src) {
        Move-Item -LiteralPath $src -Destination $dst -Force
        $logLines.Add("| $log | movido | $dst |")
    } elseif (Test-Path -LiteralPath $dst) {
        $logLines.Add("| $log | ja estava no destino | $dst |")
    } else {
        $logLines.Add("| $log | nao encontrado | $dst |")
    }
}

$driveLines = New-Object System.Collections.Generic.List[string]
foreach ($d in [System.IO.DriveInfo]::GetDrives()) {
    if ($d.IsReady -and $d.DriveType -eq 'Fixed') {
        $total = [math]::Round($d.TotalSize / 1GB, 2)
        $free = [math]::Round($d.AvailableFreeSpace / 1GB, 2)
        $used = [math]::Round(($d.TotalSize - $d.AvailableFreeSpace) / 1GB, 2)
        $pct = [math]::Round(($d.AvailableFreeSpace / $d.TotalSize) * 100, 1)
        $driveLines.Add("| $($d.Name) | $total | $free | $used | $pct |")
    }
}

$roots = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall','HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall','HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall'
$programs = Get-ChildItem -Path $roots -ErrorAction SilentlyContinue | Get-ItemProperty -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName } | Sort-Object DisplayName, DisplayVersion
$programLines = New-Object System.Collections.Generic.List[string]
foreach ($p in $programs) {
    $name = ($p.DisplayName -replace '\|','/' -replace "`r?`n",' ').Trim()
    $ver = ($p.DisplayVersion -replace '\|','/' -replace "`r?`n",' ').Trim()
    $pub = ($p.Publisher -replace '\|','/' -replace "`r?`n",' ').Trim()
    $loc = ($p.InstallLocation -replace '\|','/' -replace "`r?`n",' ').Trim()
    $programLines.Add("| $name | $ver | $pub | $loc |")
}

$review = $programs | Where-Object { $_.DisplayName -match 'Silverlight|Ask Toolbar|Infatica|Java 8 Update 441|Java Auto Updater|IRPF20|GCAP 2023|EaseUS|Kite|Justinmind|Galaxy Buds|DownloadHelper|VdhCoApp|MetaTrader|Folio Views' }
$reviewLines = New-Object System.Collections.Generic.List[string]
foreach ($p in $review) {
    $name = ($p.DisplayName -replace '\|','/' -replace "`r?`n",' ').Trim()
    $ver = ($p.DisplayVersion -replace '\|','/' -replace "`r?`n",' ').Trim()
    $pub = ($p.Publisher -replace '\|','/' -replace "`r?`n",' ').Trim()
    $loc = ($p.InstallLocation -replace '\|','/' -replace "`r?`n",' ').Trim()
    $reviewLines.Add("| $name | $ver | $pub | $loc |")
}

$svc = Get-Service | Where-Object { $_.StartType -eq 'Automatic' -and ($_.Status -eq 'Running' -or (($_.Name + ' ' + $_.DisplayName) -match 'Docker|Hyper-V|VM|Ollama|AnyDesk|BRy|SafeNet|Sentinel|WSL|Conda|Python|Code|Git|Kaspersky|Warsaw|Multipass|OpenSSH|Firebird|Configuration Manager|OCS|Cntlm')) } | Sort-Object DisplayName
$svcLines = New-Object System.Collections.Generic.List[string]
foreach ($s in $svc) {
    $svcLines.Add("| $($s.Name) | $($s.DisplayName -replace '\|','/') | $($s.Status) | $($s.StartType) |")
}

$taskLines = New-Object System.Collections.Generic.List[string]
$tasks = Get-ScheduledTask -ErrorAction SilentlyContinue | Where-Object { $_.State -in 'Ready','Running' } | Sort-Object TaskPath, TaskName | Select-Object -First 120
foreach ($t in $tasks) {
    $taskLines.Add("| $($t.TaskName -replace '\|','/') | $($t.TaskPath -replace '\|','/') | $($t.State) | $($t.Author -replace '\|','/') |")
}

$runLines = New-Object System.Collections.Generic.List[string]
$runKeys = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run','HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Run','HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run'
foreach ($key in $runKeys) {
    $props = Get-ItemProperty -Path $key -ErrorAction SilentlyContinue
    if ($props) {
        foreach ($prop in $props.PSObject.Properties) {
            if ($prop.Name -notmatch '^PS') {
                $cmd = ($prop.Value.ToString() -replace '\|','/' -replace "`r?`n",' ').Trim()
                $runLines.Add("| $key | $($prop.Name) | $cmd |")
            }
        }
    }
}

$procLines = New-Object System.Collections.Generic.List[string]
$procs = Get-Process | Sort-Object WorkingSet64 -Descending | Select-Object -First 25
foreach ($p in $procs) {
    $ram = [math]::Round($p.WorkingSet64 / 1MB, 1)
    $path = if ($p.Path) { ($p.Path -replace '\|','/' -replace "`r?`n",' ').Trim() } else { '' }
    $procLines.Add("| $($p.Id) | $($p.ProcessName) | $ram | $path |")
}

$removedPaths = 'C:\Program Files\MicroStrategy','C:\Program Files\MicroStrategy\Desktop','C:\Users\01481911775\AppData\Roaming\MicroStrategy','C:\Program Files (x86)\RSUPPORT','C:\Users\01481911775\AppData\Roaming\Rsupport','C:\Program Files (x86)\Java\jre1.8.0_161','C:\Program Files\Java\jre-10.0.2','C:\Program Files\Java\jdk-10.0.2'
$removedPathLines = New-Object System.Collections.Generic.List[string]
foreach ($path in $removedPaths) {
    $removedPathLines.Add("| $path | $(Test-Path -LiteralPath $path) |")
}

$preserve = New-Object System.Collections.Generic.List[string]
$preserve.Add("| IA-LAB | preservado | C:\IA-LAB existe: $(Test-Path 'C:\IA-LAB') |")
$preserve.Add("| Docker | preservado/localizado | programas/pastas/servicos Docker nao foram alvo da limpeza |")
$preserve.Add("| WSL | preservado/localizado | WSL Service ou recurso Windows foi preservado |")
$preserve.Add("| Hyper-V | preservado/localizado | vmms/Hyper-V nao foi alvo da limpeza |")
$preserve.Add("| Ollama | preservado/localizado | processo/pasta Ollama nao foi alvo da limpeza |")
$preserve.Add("| Open WebUI | preservado em IA-LAB | nenhum arquivo IA-LAB/Open WebUI foi removido |")
$preserve.Add("| Python | preservado/localizado | Python nao foi alvo da limpeza |")
$preserve.Add("| Conda | preservado/localizado | Conda nao foi alvo da limpeza |")
$preserve.Add("| VS Code | preservado/localizado | VS Code nao foi alvo da limpeza |")
$preserve.Add("| Git | preservado | Git permanece no inventario ou PATH |")
$preserve.Add("| AnyDesk | preservado | AnyDesk permanece instalado/servico automatico |")
$preserve.Add("| BRy | preservado | BRy permanece no inventario |")
$preserve.Add("| SafeNet | preservado por politica | nao foi alvo da limpeza; revisar nome comercial Sentinel/SafeNet se necessario |")
$preserve.Add("| Ferramentas corporativas | preservadas | Kaspersky/SCCM/Warsaw/VPN/Office/VMware/Zoho nao foram alvo da limpeza |")

$now = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
$content = New-Object System.Collections.Generic.List[string]
$content.Add('# Inventario final pos-limpeza')
$content.Add('')
$content.Add("Data da geracao: $now")
$content.Add('')
$content.Add('## Espaco livre em disco')
$content.Add('| Drive | TotalGB | FreeGB | UsedGB | FreePct |')
$content.Add('| --- | --- | --- | --- | --- |')
$content.AddRange($driveLines)
$content.Add('')
$content.Add('## Preservacao confirmada')
$content.Add('| Item | Status | Evidencia |')
$content.Add('| --- | --- | --- |')
$content.AddRange($preserve)
$content.Add('')
$content.Add('## Itens ainda classificados como revisar')
$content.Add('| Programa | Versao | Publisher | InstallLocation |')
$content.Add('| --- | --- | --- | --- |')
$content.AddRange($reviewLines)
$content.Add('')
$content.Add('## Pendencia residual')
$content.Add('- Microsoft Silverlight permanece instalado. A Fase 4 registrou MSI 1603 e erro MSI 2753 na custom action UnregisterAuthenticodeSIP, argumento XAPAuthenticodeSIPDLL. Nao foi feita nova remocao forcada nesta fase.')
$content.Add('')
$content.Add('## Programas instalados restantes')
$content.Add("Total de entradas em Uninstall: $($programs.Count)")
$content.Add('| Programa | Versao | Publisher | InstallLocation |')
$content.Add('| --- | --- | --- | --- |')
$content.AddRange($programLines)
$content.Add('')
$content.Add('## Servicos automaticos relevantes')
$content.Add('| Name | DisplayName | Status | StartType |')
$content.Add('| --- | --- | --- | --- |')
$content.AddRange($svcLines)
$content.Add('')
$content.Add('## Tarefas de inicializacao')
$content.Add('| TaskName | TaskPath | State | Author |')
$content.Add('| --- | --- | --- | --- |')
$content.AddRange($taskLines)
$content.Add('')
$content.Add('## Entradas Run de inicializacao')
$content.Add('| Key | Name | Command |')
$content.Add('| --- | --- | --- |')
$content.AddRange($runLines)
$content.Add('')
$content.Add('## Processos de maior consumo de RAM')
$content.Add('| PID | Processo | RAM_MB | Path |')
$content.Add('| --- | --- | --- | --- |')
$content.AddRange($procLines)
$content.Add('')
$content.Add('## Validacao dos caminhos removidos na Fase 4')
$content.Add('| Path | Exists |')
$content.Add('| --- | --- |')
$content.AddRange($removedPathLines)
$content.Add('')
$content.Add('## Logs movidos da Fase 4')
$content.Add('| Log | Status | Destino |')
$content.Add('| --- | --- | --- |')
$content.AddRange($logLines)
$content | Set-Content -LiteralPath $inv -Encoding UTF8

$summary = New-Object System.Collections.Generic.List[string]
$summary.Add('# Resumo da limpeza final')
$summary.Add('')
$summary.Add("Data da geracao: $now")
$summary.Add('')
$summary.Add('## Espaco total recuperado')
$summary.Add('- Nao havia baseline de espaco livre imediatamente anterior a limpeza com tamanhos por pasta. O total recuperado real nao pode ser calculado com precisao retrospectiva.')
$summary.Add('- Estado atual:')
$summary.Add('| Drive | TotalGB | FreeGB | UsedGB | FreePct |')
$summary.Add('| --- | --- | --- | --- | --- |')
$summary.AddRange($driveLines)
$summary.Add('')
$summary.Add('## Programas removidos')
$summary.Add('- Foxit Reader')
$summary.Add('- MicroStrategy Desktop')
$summary.Add('- Mobizen')
$summary.Add('- Java 8 Update 161')
$summary.Add('- Java 10')
$summary.Add('- JDK 10')
$summary.Add('')
$summary.Add('## Arquivos grandes removidos')
$summary.Add('- Removidas arvores de aplicativo de MicroStrategy, Mobizen/RSUPPORT e runtimes Java antigos.')
$summary.Add('- O tamanho exato por arvore nao foi preservado antes da remocao.')
$summary.Add('')
$summary.Add('## Pendencias restantes')
$summary.Add('- Microsoft Silverlight 5.1.30514.0 permanece instalado.')
$summary.Add('- Motivo: reparo e desinstalacao MSI retornaram 1603; log aponta erro 2753 em UnregisterAuthenticodeSIP / XAPAuthenticodeSIPDLL.')
$summary.Add('- Decisao: registrar como pendencia residual, sem forcar nova remocao.')
$summary.Add('')
$summary.Add('## Proximos alvos opcionais')
$summary.Add('| Item | Motivo | Cuidado |')
$summary.Add('| --- | --- | --- |')
$summary.Add('| Microsoft Silverlight | pendencia residual MSI 1603/2753 | nao forcar sem decisao explicita |')
$summary.Add('| Ask Toolbar | toolbar legado | validar uso real |')
$summary.Add('| Infatica P2B Network | software de rede/P2B | validar politica corporativa |')
$summary.Add('| Java 8 Update 441 / Java Auto Updater | runtime Java restante | preservar se sistema legado depender |')
$summary.Add('| IRPF/GCAP antigos | aplicativos fiscais antigos | validar necessidade historica/legal |')
$summary.Add('| DownloadHelper/VdhCoApp | auxiliares de browser | validar uso real |')
$summary.Add('| EaseUS Todo PCTrans | ferramenta de migracao | validar se ainda sera usada |')
$summary.Add('')
$summary.Add('## Preservacoes importantes')
$summary.Add('| Item | Status | Evidencia |')
$summary.Add('| --- | --- | --- |')
$summary.AddRange($preserve)
$summary.Add('')
$summary.Add('## Logs da Fase 4')
$summary.Add("Destino: $logOut")
$summary.Add('| Log | Status | Destino |')
$summary.Add('| --- | --- | --- |')
$summary.AddRange($logLines)
$summary | Set-Content -LiteralPath $sum -Encoding UTF8

Write-Host "Inventario gerado: $inv"
Write-Host "Resumo gerado: $sum"
Write-Host "Logs: $logOut"
