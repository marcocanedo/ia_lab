$ErrorActionPreference = "Stop"

$root = "C:\IA-LAB"
$dockerDir = Join-Path $root "docker"
$backupDir = Join-Path $root ("backups\llamacpp\openwebui_apply_{0:yyyyMMdd_HHmmss}" -f (Get-Date))
New-Item -ItemType Directory -Path $backupDir -Force | Out-Null

Copy-Item -LiteralPath (Join-Path $dockerDir "docker-compose.yml") -Destination (Join-Path $backupDir "docker-compose.yml") -Force
Copy-Item -LiteralPath (Join-Path $dockerDir ".env") -Destination (Join-Path $backupDir "docker.env") -Force
multipass exec ia-lab -- docker inspect -f "Name={{.Name}} Status={{.State.Status}} Health={{if .State.Health}}{{.State.Health.Status}}{{end}} Image={{.Config.Image}} Restart={{.HostConfig.RestartPolicy.Name}}" open-webui | Set-Content -Encoding UTF8 (Join-Path $backupDir "docker_open-webui_inspect.txt")
multipass exec ia-lab -- sh -lc "docker inspect -f '{{range .Config.Env}}{{println .}}{{end}}' open-webui" | Set-Content -Encoding UTF8 (Join-Path $backupDir "docker_open-webui_env.txt")

Write-Host "Backup salvo em $backupDir"
$vmComposeDir = "/home/ubuntu/ia-lab-docker"
Write-Host "Transferindo Compose para a VM em $vmComposeDir..."
multipass exec ia-lab -- mkdir -p $vmComposeDir
multipass transfer (Join-Path $dockerDir "docker-compose.yml") "ia-lab:${vmComposeDir}/docker-compose.yml"
multipass transfer (Join-Path $dockerDir ".env") "ia-lab:${vmComposeDir}/.env"

Write-Host "Validando Compose..."
multipass exec ia-lab -- sh -lc "cd $vmComposeDir && docker compose config >/tmp/ia-lab-compose-config.txt && cat /tmp/ia-lab-compose-config.txt >/dev/null"

Write-Host "Recriando somente o container open-webui pelo Compose, preservando volume externo open-webui..."
multipass exec ia-lab -- sh -lc "docker rm -f open-webui >/dev/null 2>&1 || true; cd $vmComposeDir && docker compose up -d open-webui"
if ($LASTEXITCODE -ne 0) {
    throw "Falha ao recriar open-webui via Docker Compose."
}

Write-Host "Aguardando Open WebUI..."
for ($i = 1; $i -le 90; $i++) {
    try {
        Invoke-RestMethod -Uri "http://127.0.0.1:3000/api/config" -TimeoutSec 5 | Out-Null
        Write-Host "Open WebUI respondeu em http://127.0.0.1:3000"
        exit 0
    }
    catch {
        Start-Sleep -Seconds 2
    }
}

throw "Open WebUI nao respondeu apos aplicar Compose. Consulte backup em $backupDir."
