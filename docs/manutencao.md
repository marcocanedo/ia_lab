# Manutencao

## Healthcheck

Diagnostica o ambiente e gera relatorios em `D:\IA-LAB\backups\reports`.

```powershell
D:\IA-LAB\scripts\maintenance\healthcheck.ps1
```

## Watchdog

Tenta recuperar PX, Ollama e Open WebUI quando algum deles falha.

```powershell
D:\IA-LAB\scripts\maintenance\watchdog.ps1
```

## Backup de configuracao

Salva scripts, docs, Compose, tarefas, portproxy e estado operacional.

```powershell
D:\IA-LAB\scripts\maintenance\backup_configs.ps1
```

## Snapshots e limpeza

```powershell
D:\IA-LAB\scripts\maintenance\snapshot_multipass.ps1
D:\IA-LAB\scripts\maintenance\cleanup_multipass_snapshots.ps1
D:\IA-LAB\scripts\maintenance\cleanup_logs.ps1
```

## Agendamento

Recrie as tarefas em PowerShell como Administrador:

```powershell
D:\IA-LAB\scripts\setup\configure_startup_tasks.ps1
D:\IA-LAB\scripts\setup\configure_maintenance_tasks.ps1
```
