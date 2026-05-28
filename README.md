# IA-LAB

Laboratorio local de IA com Windows, PX, Ollama, Multipass, Docker e Open WebUI.

## Acesso rapido

- Open WebUI: http://127.0.0.1:3000
- Ollama API: http://127.0.0.1:11434
- PX: http://127.0.0.1:18080

## Inicializacao

A tarefa principal do Windows Task Scheduler e `IA-LAB Startup`.

Ela chama:

```text
C:\IA-LAB\scripts\startup_apps.ps1
```

Ordem executada:

1. PX
2. Ollama
3. VM Multipass `ia-lab`
4. Portproxy `127.0.0.1:3000 -> VM:3000`

## Operacao

```powershell
cd C:\IA-LAB\scripts
.\healthcheck.ps1
.\watchdog.ps1
.\backup_configs.ps1
```

## Documentacao

Veja `docs/README.md`.
