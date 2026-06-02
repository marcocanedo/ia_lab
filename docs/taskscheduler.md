# Task Scheduler

## Tarefa principal

```text
IA-LAB Startup
```

Estado esperado: `Ready`.

Acao:

```powershell
powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -WindowStyle Hidden -File "C:\IA-LAB\scripts\startup\startup_apps.ps1"
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
C:\IA-LAB\scripts\setup\configure_startup_tasks.ps1
C:\IA-LAB\scripts\setup\configure_maintenance_tasks.ps1
```

Executar em PowerShell como Administrador.

As tarefas sao registradas como ocultas e executam o PowerShell com `-NonInteractive` e `-WindowStyle Hidden`, para operar de forma silenciosa durante o uso normal da maquina.

## Tarefas de manutencao

| Tarefa | Frequencia | Script |
| --- | --- | --- |
| IA-LAB Watchdog | a cada 5 min | `scripts\maintenance\watchdog.ps1` |
| IA-LAB Healthcheck | a cada 15 min | `scripts\maintenance\healthcheck.ps1` |
| IA-LAB Config Backup | diario 22:00 | `scripts\maintenance\backup_configs.ps1` |
| IA-LAB Multipass Snapshot | semanal domingo 23:00 | `scripts\maintenance\snapshot_multipass.ps1` + retencao `auto-*` dos ultimos 4 |
| IA-LAB Cleanup Logs | semanal domingo 23:30 | `scripts\maintenance\cleanup_logs.ps1` |

## Modo silencioso

A proposta atual usa o Task Scheduler como mecanismo "service-like": ele roda em segundo plano, inicia quando disponivel, evita instancias duplicadas e nao depende de janela interativa visivel.

Um Windows Service real tambem seria possivel, mas exigiria um wrapper como WinSW/NSSM ou um executavel proprio de servico. Para estes scripts periodicos, o Task Scheduler e mais simples, audita melhor o historico de execucao e evita manter um processo residente apenas para chamar verificacoes curtas.

## Healthcheck

O healthcheck valida:

- PX
- Ollama GPU, CPU e roteador
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
