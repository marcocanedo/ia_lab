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
- `IA-LAB Ollama Startup`
- `IA-LAB Apps Startup`

## Manutencao

Script de configuracao:

```powershell
D:\IA-LAB\scripts\setup\configure_startup_tasks.ps1
D:\IA-LAB\scripts\setup\configure_maintenance_tasks.ps1
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
- processos monitorados no host, por padrao `px` e `ollama`
- Ollama GPU, CPU e roteador
- Multipass
- Docker
- Open WebUI
- Portproxy
- portas
- APIs

Relatorios:

```text
D:\IA-LAB\scripts\logs\healthcheck
```
