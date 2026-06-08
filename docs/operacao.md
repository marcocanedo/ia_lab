# Operacao diaria

## Comandos principais

```powershell
cd C:\IA-LAB
.\scripts\maintenance\healthcheck.ps1
.\scripts\maintenance\watchdog.ps1
.\scripts\maintenance\backup_configs.ps1
```

## Estado esperado

- Open WebUI responde em <http://127.0.0.1:3000>.
- Ollama router responde em <http://127.0.0.1:11436/api/tags>.
- VM `ia-lab` esta `Running`.
- Container `open-webui` esta `running` e `healthy`.
- Portproxy local aponta `127.0.0.1:3000` para o IP atual da VM.

## Validar Gemma 4 12B GPU

```powershell
Invoke-RestMethod http://127.0.0.1:11436/api/tags
$body = @{ model = "gemma4:12b-gpu"; prompt = "Responda apenas: ok"; stream = $false } | ConvertTo-Json
Invoke-RestMethod -Method Post -Uri http://127.0.0.1:11436/api/generate -ContentType "application/json" -Body $body
Invoke-RestMethod http://127.0.0.1:11434/api/ps
nvidia-smi
```

## Inicializacao manual

```powershell
C:\IA-LAB\scripts\startup\startup_apps.ps1
```

Ordem executada:

1. PX.
2. Ollama GPU, CPU e roteador.
3. VM Multipass `ia-lab`.
4. Portproxy local do Open WebUI.

## Proximos links

- [Startup flow](startup_flow.md)
- [Task Scheduler](taskscheduler.md)
- [Manutencao](manutencao.md)
