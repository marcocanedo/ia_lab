# Manutencao

## Healthcheck

Diagnostica o ambiente e gera relatorios em `C:\IA-LAB\backups\reports`.

```powershell
C:\IA-LAB\scripts\maintenance\healthcheck.ps1
```

## Watchdog

Tenta recuperar PX, Ollama e Open WebUI quando algum deles falha.

```powershell
C:\IA-LAB\scripts\maintenance\watchdog.ps1
```

## Backup de configuracao

Salva scripts, docs, Compose, tarefas, portproxy e estado operacional.

```powershell
C:\IA-LAB\scripts\maintenance\backup_configs.ps1
```

## Snapshots e limpeza

```powershell
C:\IA-LAB\scripts\maintenance\snapshot_multipass.ps1
C:\IA-LAB\scripts\maintenance\cleanup_multipass_snapshots.ps1
C:\IA-LAB\scripts\maintenance\cleanup_logs.ps1
```

## Agendamento

Recrie as tarefas em PowerShell como Administrador:

```powershell
C:\IA-LAB\scripts\setup\configure_startup_tasks.ps1
C:\IA-LAB\scripts\setup\configure_maintenance_tasks.ps1
```
