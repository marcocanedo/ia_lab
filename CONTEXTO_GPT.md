# Contexto geral do IA-LAB para GPT

Atualizado em: 2026-07-03

Este documento resume o estado atual do projeto para ser usado como briefing tecnico.

## Objetivo

O IA-LAB e um laboratorio de infraestrutura base em Windows com PX, Multipass, uma VM Ubuntu chamada `ia-lab` e scripts de suporte. Nenhum backend de IA fica ativo no caminho principal.

O objetivo operacional e permitir:

- PX acessivel em `http://127.0.0.1:18080`.
- VM `ia-lab` disponivel via Multipass.
- SSH remoto na VM usando o IP atual.
- Inicializacao e manutencao automatizadas pelo Windows Task Scheduler.
- Healthcheck, watchdog e limpeza de logs periodicos.

## Arquitetura

Fluxo principal:

```text
Windows Host
  -> PX em 127.0.0.1:18080
  -> Multipass service
  -> VM Ubuntu ia-lab
  -> SSH / VS Code Remote / comandos administrativos
```

Componentes:

- Windows Host: executa PX, Task Scheduler, scripts e ferramentas de suporte.
- PX: proxy NTLM local em `127.0.0.1:18080`.
- Multipass: gerencia a VM Ubuntu chamada `ia-lab`.
- VM `ia-lab`: executa SSH e utilitarios basicos de suporte.

## Portas

| Porta | Camada | Servico | Uso |
| --- | --- | --- | --- |
| 18080 | Windows | PX | Proxy NTLM local |
| 22 | VM | SSH | Acesso remoto ao host `ia-lab` |

## Scripts principais

Pasta raiz:

```text
D:\IA-LAB\scripts
```

Inicializacao (`D:\IA-LAB\scripts\startup`):

- `startup_vm.ps1`: inicia Multipass e a VM `ia-lab`, sincroniza o IP e atualiza o SSH do usuario quando necessario.
- `startup_px.ps1`: inicia PX e aguarda porta `18080`.
- `startup_apps.ps1`: orquestra PX e revalida a VM no logon.
- `update_ssh_config.ps1`: atualiza `~\.ssh\config` para apontar para o IP atual da VM e injeta a chave publica.

Operacao e manutencao (`D:\IA-LAB\scripts\maintenance`):

- `healthcheck.ps1`: valida PX, Multipass, VM e SSH.
- `watchdog.ps1`: tenta recuperar PX e a VM base quando indisponiveis.
- `cleanup_logs.ps1`: remove logs e relatorios antigos.

Setup (`D:\IA-LAB\scripts\setup`):

- `configure_startup_tasks.ps1`: registra as tarefas principais de boot e logon.
- `configure_maintenance_tasks.ps1`: registra tarefas periodicas de manutencao.
- `configure_vm_proxy.ps1`: configura proxy APT dentro da VM.
- `setup_px_proxy.ps1`: registra o PX para uso corporativo quando necessario.
- `rebuild_multipass_vm.ps1`: recria a VM `ia-lab`.
- `git_setup.ps1`: configura Git local/global para uso com proxy PX quando necessario.

Artefatos historicos ficam em `D:\IA-LAB\archive`.

## Task Scheduler

As tarefas principais sao:

```text
IA-LAB VM Boot
IA-LAB Host Services
```

Acao:

```powershell
powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -WindowStyle Hidden -File "D:\IA-LAB\scripts\startup\startup_vm.ps1"
powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -WindowStyle Hidden -File "D:\IA-LAB\scripts\startup\startup_apps.ps1"
```

Gatilhos:

- At startup, delay 30 segundos.
- At logon, delay 20 segundos.

Tarefas de manutencao:

| Tarefa | Frequencia | Script |
| --- | --- | --- |
| IA-LAB Watchdog | a cada 5 min | `scripts\maintenance\watchdog.ps1` |
| IA-LAB Healthcheck | a cada 15 min | `scripts\maintenance\healthcheck.ps1` |
| IA-LAB Cleanup Logs | semanal domingo 23:30 | `scripts\maintenance\cleanup_logs.ps1` |

As tarefas sao registradas como ocultas e usam `-NonInteractive` e `-WindowStyle Hidden`.

## Healthcheck

Script:

```powershell
D:\IA-LAB\scripts\maintenance\healthcheck.ps1
```

Valida:

- PX na porta `18080`.
- Processo `px`.
- Servico Multipass.
- VM `ia-lab` em estado `Running`.
- Execucao remota via `multipass exec`.
- SSH na VM na porta `22`.
- Entrada SSH local sincronizada com o IP atual da VM.

## Watchdog

Script:

```powershell
D:\IA-LAB\scripts\maintenance\watchdog.ps1
```

Funcao:

- Se PX estiver indisponivel, chama `startup_px.ps1`.
- Se a VM base estiver indisponivel, chama `startup_vm.ps1`.

## Rebuild da VM

Script:

```powershell
D:\IA-LAB\scripts\setup\rebuild_multipass_vm.ps1
```

O fluxo base recria a VM, configura o proxy APT via PX e valida SSH.
