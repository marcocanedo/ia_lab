$ErrorActionPreference = 'Continue'

$OneDriveRoot = Get-ChildItem -LiteralPath $env:USERPROFILE -Directory -Force |
    Where-Object { $_.Name -like 'OneDrive - Secretaria da Fazenda do Paran*' } |
    Select-Object -First 1

if ($null -eq $OneDriveRoot) {
    throw "OneDrive root not found under $env:USERPROFILE"
}

$BackupRoot = Join-Path $OneDriveRoot.FullName 'BACKUP_WORKSTATION_2026'
$OutDir = 'C:\inventario_migracao_workstation'
$Manifest = Join-Path $OutDir 'manifesto_backup_final.csv'
$OldManifest = Join-Path $OutDir 'manifesto_backup_final_resumo_validacao.csv'
$Summary = Join-Path $OutDir 'manifesto_backup_final_resumo.md'
$MaxHashBytes = 500MB
$Phase6SizeGb = 2.39
$Phase6Files = 36490

if (-not (Test-Path -LiteralPath $BackupRoot -PathType Container)) {
    throw "Backup root not found: $BackupRoot"
}

if (-not (Test-Path -LiteralPath $OutDir -PathType Container)) {
    New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
}

if ((Test-Path -LiteralPath $Manifest -PathType Leaf) -and -not (Test-Path -LiteralPath $OldManifest -PathType Leaf)) {
    Copy-Item -LiteralPath $Manifest -Destination $OldManifest -Force:$false
}

function Format-SizeHuman([Int64]$Bytes) {
    if ($Bytes -ge 1GB) { return ('{0:N2} GB' -f ($Bytes / 1GB)) }
    if ($Bytes -ge 1MB) { return ('{0:N2} MB' -f ($Bytes / 1MB)) }
    if ($Bytes -ge 1KB) { return ('{0:N2} KB' -f ($Bytes / 1KB)) }
    return "$Bytes B"
}

function Get-SensitivityFlag([string]$Path) {
    $patterns = @('.ssh', '.env', 'key', 'token', 'secret', 'credential', 'password', 'senha', 'certificado', 'cert', 'id_ed25519', 'sqlite', 'db', 'dump', 'backup', 'codex', 'ollama')
    $lower = $Path.ToLowerInvariant()
    foreach ($pattern in $patterns) {
        if ($lower.Contains($pattern.ToLowerInvariant())) {
            return 'sensitive_possible'
        }
    }
    return 'normal'
}

function ConvertTo-CsvField([object]$Value) {
    if ($null -eq $Value) { return '""' }
    $text = [string]$Value
    $text = $text.Replace('"', '""')
    return '"' + $text + '"'
}

$tmpManifest = "$Manifest.tmp"
$writer = New-Object System.IO.StreamWriter($tmpManifest, $false, ([System.Text.Encoding]::UTF8))
$writer.WriteLine('relative_path,full_path,size_bytes,size_human,last_write_time,creation_time,extension,directory,sha256,hash_status,sensitivity_flag,notes')

$totalFiles = 0
$totalBytes = [Int64]0
$hashOk = 0
$skippedLarge = 0
$accessErrors = 0
$withoutHash = 0
$sensitiveCount = 0
$topFiles = New-Object System.Collections.Generic.List[object]
$extCounts = @{}
$rootCounts = @{}

try {
    Get-ChildItem -LiteralPath $BackupRoot -Recurse -File -Force -ErrorAction SilentlyContinue | ForEach-Object {
        $file = $_
        $relative = $file.FullName.Substring($BackupRoot.Length).TrimStart('\')
        $sha = ''
        $hashStatus = ''
        $notes = ''

        try {
            if ($file.Length -gt $MaxHashBytes) {
                $hashStatus = 'skipped_large_file'
                $notes = 'Hash skipped because file is larger than 500 MB.'
                $skippedLarge++
                $withoutHash++
            } else {
                $sha = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256 -ErrorAction Stop).Hash
                $hashStatus = 'ok'
                $hashOk++
            }
        } catch [System.UnauthorizedAccessException] {
            $hashStatus = 'access_denied'
            $notes = $_.Exception.Message
            $accessErrors++
            $withoutHash++
        } catch {
            if ($_.Exception.Message -like '*existe*' -or $_.Exception.Message -like '*localizar*' -or $_.Exception.Message -like '*does not exist*' -or $_.Exception.Message -like '*cannot find*') {
                $hashStatus = 'path_not_found'
            } else {
                $hashStatus = 'error'
            }
            $notes = $_.Exception.Message
            $accessErrors++
            $withoutHash++
        }

        $sensitivity = Get-SensitivityFlag $relative
        if ($sensitivity -eq 'sensitive_possible') { $sensitiveCount++ }

        $totalFiles++
        $totalBytes += [Int64]$file.Length

        $ext = $file.Extension
        if ([string]::IsNullOrWhiteSpace($ext)) { $ext = '(sem extensao)' }
        if (-not $extCounts.ContainsKey($ext)) { $extCounts[$ext] = 0 }
        $extCounts[$ext]++

        $root = ($relative -split '\\')[0]
        if (-not $rootCounts.ContainsKey($root)) { $rootCounts[$root] = 0 }
        $rootCounts[$root]++

        $topFiles.Add([pscustomobject]@{
            relative_path = $relative
            size_bytes = [Int64]$file.Length
            size_human = Format-SizeHuman ([Int64]$file.Length)
            hash_status = $hashStatus
            sensitivity_flag = $sensitivity
        }) | Out-Null

        $fields = @(
            $relative,
            $file.FullName,
            $file.Length,
            (Format-SizeHuman ([Int64]$file.Length)),
            $file.LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss'),
            $file.CreationTime.ToString('yyyy-MM-dd HH:mm:ss'),
            $file.Extension,
            $file.DirectoryName,
            $sha,
            $hashStatus,
            $sensitivity,
            $notes
        ) | ForEach-Object { ConvertTo-CsvField $_ }

        $writer.WriteLine(($fields -join ','))
    }
} finally {
    $writer.Flush()
    $writer.Close()
}

Move-Item -LiteralPath $tmpManifest -Destination $Manifest -Force

$totalGb = $totalBytes / 1GB
$gbDiff = $totalGb - $Phase6SizeGb
$fileDiff = $totalFiles - $Phase6Files
$compatible = ([Math]::Abs($gbDiff) -le 0.25)
if ($compatible) {
    $compatText = 'COMPATIVEL com a Fase 6 por tamanho aproximado. A contagem de arquivos pode divergir por diferenca de escopo, metadados ou arquivos auxiliares do OneDrive.'
} else {
    $compatText = 'ATENCAO: tamanho calculado diverge significativamente da Fase 6.'
}

$top20 = $topFiles | Sort-Object size_bytes -Descending | Select-Object -First 20
$extSorted = $extCounts.GetEnumerator() | Sort-Object Value -Descending
$rootSorted = $rootCounts.GetEnumerator() | Sort-Object Value -Descending

$md = New-Object System.Collections.Generic.List[string]
$md.Add('# Manifesto tecnico final do backup')
$md.Add('')
$md.Add('Data: ' + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))
$md.Add('')
$md.Add('## Escopo')
$md.Add('- Backup validado: `' + $BackupRoot + '`')
$md.Add('- Manifesto tecnico: `' + $Manifest + '`')
$md.Add('- Manifesto anterior preservado como: `' + $OldManifest + '`')
$md.Add('')
$md.Add('## Totais')
$md.Add('- Total de arquivos listados: ' + $totalFiles)
$md.Add('- Tamanho total em bytes: ' + $totalBytes)
$md.Add('- Tamanho total em GB: ' + ('{0:N3}' -f $totalGb))
$md.Add('- Total de arquivos com hash calculado: ' + $hashOk)
$md.Add('- Total de arquivos ignorados por tamanho: ' + $skippedLarge)
$md.Add('- Total de arquivos com erro de hash/acesso: ' + $accessErrors)
$md.Add('- Total de arquivos marcados como sensiveis possiveis: ' + $sensitiveCount)
$md.Add('')
$md.Add('## Comparacao com a Fase 6')
$md.Add('- Fase 6 estimava: 2,39 GB e 36.490 arquivos.')
$md.Add('- Fase 7B calculou: ' + ('{0:N3}' -f $totalGb) + ' GB e ' + $totalFiles + ' arquivos.')
$md.Add('- Diferenca de tamanho: ' + ('{0:N3}' -f $gbDiff) + ' GB.')
$md.Add('- Diferenca de arquivos: ' + $fileDiff + '.')
$md.Add('- Resultado: ' + $compatText)
$md.Add('- Observacao: pequena diferenca nao deve ser tratada como erro se o OneDrive alterou metadados ou arquivos auxiliares.')
$md.Add('')
$md.Add('## Top 20 maiores arquivos')
$md.Add('| # | tamanho | bytes | caminho relativo | hash_status | sensibilidade |')
$md.Add('|---:|---:|---:|---|---|---|')
$i = 1
foreach ($r in $top20) {
    $md.Add('| ' + $i + ' | ' + $r.size_human + ' | ' + $r.size_bytes + ' | `' + $r.relative_path + '` | ' + $r.hash_status + ' | ' + $r.sensitivity_flag + ' |')
    $i++
}
$md.Add('')
$md.Add('## Contagem por extensao')
$md.Add('| extensao | quantidade |')
$md.Add('|---|---:|')
foreach ($g in $extSorted) {
    $md.Add('| `' + $g.Key + '` | ' + $g.Value + ' |')
}
$md.Add('')
$md.Add('## Contagem por diretorio raiz')
$md.Add('| diretorio raiz | quantidade |')
$md.Add('|---|---:|')
foreach ($g in $rootSorted) {
    $md.Add('| `' + $g.Key + '` | ' + $g.Value + ' |')
}
$md.Add('')
$md.Add('## Pendencias conhecidas')
$md.Add('- Microsoft Silverlight permanece como pendencia residual.')
$md.Add('- `C:\Users\01481911775\.ssh\multipass_ia_lab` nao foi copiado por acesso negado.')
$md.Add('- Recomenda-se recriar chave/instancia Multipass na nova workstation se necessario.')
$md.Add('- Backup validado anteriormente como consistente e pronto para restauracao.')
$md.Add('- Aguardar sincronizacao completa do OneDrive antes de desligar, formatar ou devolver a maquina antiga.')
$md.Add('')
$md.Add('## Resultado final')
if ($accessErrors -eq 0 -and $compatible) {
    $status = 'pronto com pendencias conhecidas'
} elseif ($accessErrors -eq 0) {
    $status = 'atencao'
} else {
    $status = 'atencao com erros de hash/acesso'
}
$md.Add('- Status geral: ' + $status)
$md.Add('- Arquivos sem hash: ' + $withoutHash)
$md.Add('- Erros: ' + $accessErrors)
$md | Set-Content -LiteralPath $Summary -Encoding UTF8

Write-Host "manifesto=$Manifest"
Write-Host "summary=$Summary"
Write-Host "files=$totalFiles"
Write-Host "hashes=$hashOk"
Write-Host "without_hash=$withoutHash"
Write-Host "errors=$accessErrors"
Write-Host "total_bytes=$totalBytes"
Write-Host ('total_gb={0:N3}' -f $totalGb)
Write-Host "phase6_compatible=$compatible"
Write-Host "old_manifest_preserved=$OldManifest"
