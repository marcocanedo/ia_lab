# Task Scheduler

## Tarefas principais

```text
IA-LAB VM Boot
IA-LAB Host Services
```

Estado esperado: `Ready` ou `Running`, conforme o gatilho.

Acao `IA-LAB VM Boot`:

```powershell
powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -WindowStyle Hidden -File "D:\IA-LAB\scripts\startup\startup_vm.ps1"
```

Acao `IA-LAB Host Services`:

```powershell
powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -WindowStyle Hidden -File "D:\IA-LAB\scripts\startup\startup_apps.ps1"
```

Gatilhos:

- `IA-LAB VM Boot`: At startup, delay 30s, usuario `SYSTEM`
- `IA-LAB Host Services`: At logon, delay 20s, usuario interativo

## Tarefas antigas

Devem permanecer desabilitadas:

- `IA-LAB Startup`
- `IA-LAB PX Startup`
- `IA-LAB Apps Startup`
- `IA-LAB WSL Boot`
- `IA-LAB Multipass Boot`

## Manutencao

Script de configuracao:

```powershell
D:\IA-LAB\scripts\setup\configure_startup_tasks.ps1
D:\IA-LAB\scripts\setup\configure_maintenance_tasks.ps1
```

Executar em PowerShell como Administrador.

As tarefas sao registradas como ocultas e executam o PowerShell com `-NonInteractive` e `-WindowStyle Hidden`.

## Tarefas de manutencao

| Tarefa | Frequencia | Script |
| --- | --- | --- |
| IA-LAB Watchdog | a cada 5 min | `scripts\maintenance\watchdog.ps1` |
| IA-LAB Healthcheck | a cada 15 min | `scripts\maintenance\healthcheck.ps1` |
| IA-LAB Cleanup Logs | semanal domingo 23:30 | `scripts\maintenance\cleanup_logs.ps1` |

## Healthcheck

O healthcheck valida:

- PX
- processo `px`
- servico Multipass
- VM `ia-lab`
- execucao remota via Multipass
- SSH na VM
- sincronizacao da configuracao SSH local

Relatorios:

```text
D:\IA-LAB\scripts\logs\healthcheck
```
