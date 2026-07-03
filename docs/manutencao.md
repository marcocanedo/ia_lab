# Manutencao

## Healthcheck

Diagnostica o ambiente e gera relatorios em `D:\IA-LAB\scripts\logs\healthcheck`.

```powershell
D:\IA-LAB\scripts\maintenance\healthcheck.ps1
```

## Watchdog

Tenta recuperar PX e a VM base quando algum deles falha.

```powershell
D:\IA-LAB\scripts\maintenance\watchdog.ps1
```

## Limpeza de logs

Remove logs e relatorios antigos conforme retencao padrao.

```powershell
D:\IA-LAB\scripts\maintenance\cleanup_logs.ps1
```

## Agendamento

Recrie as tarefas em PowerShell como Administrador:

```powershell
D:\IA-LAB\scripts\setup\configure_startup_tasks.ps1
D:\IA-LAB\scripts\setup\configure_maintenance_tasks.ps1
```
