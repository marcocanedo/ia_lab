$ErrorActionPreference = "Stop"

$root = "C:\IA-LAB"
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$backupRoot = Join-Path $root "backups\configs\$timestamp"

New-Item -ItemType Directory -Force -Path $backupRoot | Out-Null

function Save-CommandOutput {
    param(
        [scriptblock]$ScriptBlock,
        [string]$OutputPath,
        [int]$TimeoutSeconds = 30
    )

    $job = Start-Job -ScriptBlock $ScriptBlock
    $completed = Wait-Job $job -Timeout $TimeoutSeconds

    if ($completed) {
        Receive-Job $job 2>&1 | Set-Content -Encoding UTF8 $OutputPath
    }
    else {
        Stop-Job $job
        "TIMEOUT after $TimeoutSeconds seconds" | Set-Content -Encoding UTF8 $OutputPath
    }

    Remove-Job $job -Force
}

function Save-ProcessOutput {
    param(
        [string]$FilePath,
        [string[]]$ArgumentList,
        [string]$OutputPath,
        [int]$TimeoutSeconds = 45
    )

    $tempOut = [System.IO.Path]::GetTempFileName()
    $tempErr = [System.IO.Path]::GetTempFileName()

    try {
        $process = Start-Process `
            -FilePath $FilePath `
            -ArgumentList $ArgumentList `
            -NoNewWindow `
            -PassThru `
            -RedirectStandardOutput $tempOut `
            -RedirectStandardError $tempErr

        if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
            $process.Kill()
            "TIMEOUT after $TimeoutSeconds seconds" | Set-Content -Encoding UTF8 $OutputPath
            return
        }

        $output = @()
        $output += Get-Content $tempOut -ErrorAction SilentlyContinue
        $errors = Get-Content $tempErr -ErrorAction SilentlyContinue
        if ($errors) {
            $output += $errors
        }

        if (-not $output) {
            $output = @("ExitCode: $($process.ExitCode)")
        }

        $output | Set-Content -Encoding UTF8 $OutputPath
    }
    finally {
        Remove-Item -LiteralPath $tempOut, $tempErr -Force -ErrorAction SilentlyContinue
    }
}

Copy-Item -Recurse -Force -Path (Join-Path $root "scripts") -Destination (Join-Path $backupRoot "scripts")
Copy-Item -Recurse -Force -Path (Join-Path $root "docs") -Destination (Join-Path $backupRoot "docs") -ErrorAction SilentlyContinue
Copy-Item -Recurse -Force -Path (Join-Path $root "docker") -Destination (Join-Path $backupRoot "docker") -ErrorAction SilentlyContinue
Copy-Item -Recurse -Force -Path (Join-Path $root ".vscode") -Destination (Join-Path $backupRoot ".vscode") -ErrorAction SilentlyContinue
Copy-Item -Force -Path (Join-Path $root "README.md") -Destination (Join-Path $backupRoot "README.md") -ErrorAction SilentlyContinue
Copy-Item -Force -Path (Join-Path $root ".gitignore") -Destination (Join-Path $backupRoot ".gitignore") -ErrorAction SilentlyContinue
Copy-Item -Force -Path (Join-Path $root "IA-LAB.code-workspace") -Destination (Join-Path $backupRoot "IA-LAB.code-workspace") -ErrorAction SilentlyContinue

Save-CommandOutput { Export-ScheduledTask -TaskName "IA-LAB Startup" } (Join-Path $backupRoot "task_IA-LAB_Startup.xml")
Save-CommandOutput { Get-ScheduledTask -TaskName "IA-LAB*" -ErrorAction SilentlyContinue | Format-List * } (Join-Path $backupRoot "tasks.txt")
Save-CommandOutput { netsh interface portproxy show all } (Join-Path $backupRoot "portproxy.txt")
Save-ProcessOutput "multipass" @("info", "ia-lab") (Join-Path $backupRoot "multipass_ia-lab.txt")
multipass exec ia-lab -- sh -lc "docker inspect -f 'Name={{.Name}} Status={{.State.Status}} Health={{if .State.Health}}{{.State.Health.Status}}{{end}} Image={{.Config.Image}} Restart={{.HostConfig.RestartPolicy.Name}}' open-webui" | Set-Content -Encoding UTF8 (Join-Path $backupRoot "docker_open-webui_inspect.txt")
multipass exec ia-lab -- sh -lc "docker inspect -f '{{range .Config.Env}}{{println .}}{{end}}' open-webui" | Set-Content -Encoding UTF8 (Join-Path $backupRoot "docker_open-webui_env.txt")
Save-ProcessOutput "multipass" @("exec", "ia-lab", "--", "docker", "volume", "ls") (Join-Path $backupRoot "docker_volumes.txt") 30

$archive = Join-Path $root "backups\configs\ia-lab-configs_$timestamp.zip"
Compress-Archive -Path (Join-Path $backupRoot "*") -DestinationPath $archive -Force

Write-Output "Backup criado: $archive"
