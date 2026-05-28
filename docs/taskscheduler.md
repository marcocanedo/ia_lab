# Task Scheduler

## Tarefa principal

```text
IA-LAB Startup
```

Estado esperado: `Ready`.

Acao:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "C:\IA-LAB\scripts\startup_apps.ps1"
```

Gatilhos:

- At startup, delay 30s
- At logon, delay 30s

## Tarefas antigas

Devem permanecer desabilitadas:

- `IA-LAB PX Startup`
- `IA-LAB Ollama Startup`
- `IA-LAB Apps Startup`

## Manutencao

Script de configuracao:

```powershell
C:\IA-LAB\scripts\configure_startup_tasks.ps1
C:\IA-LAB\scripts\configure_maintenance_tasks.ps1
```

Executar em PowerShell como Administrador.

## Tarefas de manutencao

| Tarefa | Frequencia | Script |
| --- | --- | --- |
| IA-LAB Watchdog | a cada 5 min | `watchdog.ps1` |
| IA-LAB Healthcheck | a cada 15 min | `healthcheck.ps1` |
| IA-LAB Config Backup | diario 22:00 | `backup_configs.ps1` |
| IA-LAB Multipass Snapshot | semanal domingo 23:00 | `snapshot_multipass.ps1` + retencao `auto-*` dos ultimos 4 |
| IA-LAB Cleanup Logs | semanal domingo 23:30 | `cleanup_logs.ps1` |

## Healthcheck

O healthcheck valida:

- PX
- Ollama
- Multipass
- Docker
- Open WebUI
- Portproxy
- portas
- APIs

Relatorios:

```text
C:\IA-LAB\backups\reports
```
