# Contexto geral do IA-LAB para GPT

Atualizado em: 2026-06-01

Este documento resume o projeto IA-LAB para ser enviado a outro GPT ou usado como briefing tecnico.

## Objetivo

O IA-LAB e um laboratorio local de IA em Windows, com Ollama para modelos locais, Open WebUI como interface web, PX como proxy NTLM local e uma VM Ubuntu Multipass para isolar a camada Docker.

O objetivo operacional e permitir uso local de IA com:

- Open WebUI acessivel em `http://127.0.0.1:3000`.
- Ollama router acessivel em `http://127.0.0.1:11436`.
- Ollama GPU/CPU acessiveis localmente em `11434`/`11435`.
- PX proxy local acessivel em `http://127.0.0.1:18080`.
- Inicializacao e manutencao automatizadas pelo Windows Task Scheduler.
- Backups, healthchecks, watchdog e snapshots periodicos.

## Arquitetura

Fluxo principal:

```text
Browser
  -> 127.0.0.1:3000
  -> Windows portproxy
  -> VM Multipass ia-lab:3000
  -> Docker container open-webui:8080
  -> Ollama router no Windows:11436
  -> Ollama GPU 11434 ou CPU 11435
```

Componentes:

- Windows Host: executa PX, Ollama, Task Scheduler, portproxy, VSCode e browser.
- PX: proxy NTLM local em `127.0.0.1:18080`.
- Ollama: roda no Windows, com GPU em `0.0.0.0:11434`, CPU em `0.0.0.0:11435` e roteador em `0.0.0.0:11436`.
- Multipass: gerencia a VM Ubuntu chamada `ia-lab`.
- Docker: roda dentro da VM `ia-lab`.
- Open WebUI: container Docker `open-webui`, publicado na VM na porta `3000`.

## Portas

| Porta | Camada | Servico | Uso |
| --- | --- | --- | --- |
| 18080 | Windows | PX | Proxy NTLM local |
| 11434 | Windows | Ollama GPU | Backend GPU |
| 11435 | Windows | Ollama CPU | Backend CPU `cpu_avx2` |
| 11436 | Windows | Ollama Router | Endpoint usado pelo Open WebUI |
| 3000 | Windows | Portproxy | Entrada local do Open WebUI |
| 3000 | VM | Docker publish | Porta host da VM para Open WebUI |
| 8080 | Container | Open WebUI | Porta interna do app |

O portproxy esperado segue este formato:

```text
127.0.0.1:3000 -> IP_ATUAL_DA_VM:3000
```

O IP da VM pode mudar a cada boot, entao `startup_vm.ps1` detecta o IP atual e recria o portproxy.

Estado validado em 2026-06-01:

```text
127.0.0.1:3000 -> 172.25.122.220:3000
```

Pendencia: existe um portproxy corporativo antigo `10.14.0.226:3000 -> 172.21.150.39:3000`, apontando para IP anterior da VM.

## Docker e Open WebUI

O Compose fica em:

```text
C:\IA-LAB\docker\docker-compose.yml
```

Pontos relevantes:

- Container: `open-webui`.
- Imagem: `ghcr.io/open-webui/open-webui:${OPEN_WEBUI_TAG:-main}`.
- Porta publicada: `${OPEN_WEBUI_HOST_PORT:-3000}:8080`.
- Volume persistente externo: `open-webui`.
- Healthcheck interno: `http://127.0.0.1:8080/api/config`.
- Proxy HTTP/HTTPS/ALL_PROXY e variantes em minusculo sao limpos dentro do container para evitar que chamadas ao Ollama passem por proxy indevido.
- `OLLAMA_BASE_URLS` e `OLLAMA_BASE_URL` sao mantidos por compatibilidade entre versoes do Open WebUI.
- O endpoint atual do Open WebUI e `http://10.14.0.226:11436`.

Arquivo de exemplo de ambiente:

```text
C:\IA-LAB\docker\.env.example
```

O arquivo real `docker\.env` e local e fica ignorado no Git.

## Scripts principais

Pasta raiz:

```text
C:\IA-LAB\scripts
```

Inicializacao (`C:\IA-LAB\scripts\startup`):

- `startup_apps.ps1`: orquestra a inicializacao geral.
- `startup_px.ps1`: inicia PX e aguarda porta `18080`.
- `startup_ollama.ps1`: configura variaveis do Ollama/proxy, inicia backend GPU `11434`, backend CPU `11435` e roteador `11436`.
- `ollama_router.ps1`: roteia requisicoes do Open WebUI para GPU ou CPU por modelo.
- `startup_vm.ps1`: inicia VM `ia-lab`, detecta IP, atualiza SSH config, recria portproxy e aguarda Open WebUI na porta `3000`.
- `update_ssh_config.ps1`: atualiza `~\.ssh\config` para VSCode Remote acessar a VM.

Operacao e manutencao (`C:\IA-LAB\scripts\maintenance`):

- `healthcheck.ps1`: valida saude geral e gera relatorios JSON/TXT.
- `watchdog.ps1`: tenta recuperar PX, Ollama ou Open WebUI quando indisponiveis.
- `backup_configs.ps1`: cria backup de scripts, docs, compose, tarefas, portproxy e estado operacional.
- `snapshot_multipass.ps1`: cria snapshot automatico da VM.
- `cleanup_multipass_snapshots.ps1`: mantem apenas os ultimos snapshots automaticos `auto-*`.
- `cleanup_logs.ps1`: remove logs e relatorios antigos.

Setup (`C:\IA-LAB\scripts\setup`):

- `configure_startup_tasks.ps1`: registra tarefa principal de startup.
- `configure_maintenance_tasks.ps1`: registra tarefas periodicas de manutencao.
- `configure_vm_proxy.ps1`: configura proxy APT dentro da VM.
- `git_setup.ps1`: configura Git local/global para uso com proxy PX quando necessario.

Ferramentas auxiliares (`C:\IA-LAB\scripts\tools`) guardam inventario, rankings de consumo e manifesto de backup. Artefatos historicos ficam em `C:\IA-LAB\archive`.

## Task Scheduler

A tarefa principal e:

```text
IA-LAB Startup
```

Acao:

```powershell
powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -WindowStyle Hidden -File "C:\IA-LAB\scripts\startup\startup_apps.ps1"
```

Gatilhos:

- At startup, delay 30 segundos.
- At logon, delay 30 segundos.

Ordem executada pelo startup:

1. PX.
2. Ollama GPU, CPU e roteador.
3. VM Multipass `ia-lab`.
4. Portproxy `127.0.0.1:3000 -> VM:3000`.

Tarefas de manutencao:

| Tarefa | Frequencia | Script |
| --- | --- | --- |
| IA-LAB Watchdog | a cada 5 min | `scripts\maintenance\watchdog.ps1` |
| IA-LAB Healthcheck | a cada 15 min | `scripts\maintenance\healthcheck.ps1` |
| IA-LAB Config Backup | diario 22:00 | `scripts\maintenance\backup_configs.ps1` |
| IA-LAB Multipass Snapshot | semanal domingo 23:00 | `scripts\maintenance\snapshot_multipass.ps1` |
| IA-LAB Cleanup Logs | semanal domingo 23:30 | `scripts\maintenance\cleanup_logs.ps1` |

As tarefas sao registradas como ocultas e usam `-NonInteractive` e `-WindowStyle Hidden`, para operar de forma silenciosa, semelhante a um servico, sem abrir janelas durante o uso normal da maquina.

Para registrar ou atualizar as tarefas reais no Windows, executar em PowerShell como Administrador:

```powershell
C:\IA-LAB\scripts\setup\configure_startup_tasks.ps1
C:\IA-LAB\scripts\setup\configure_maintenance_tasks.ps1
```

## Healthcheck

Script:

```powershell
C:\IA-LAB\scripts\maintenance\healthcheck.ps1
```

Valida:

- PX na porta `18080`.
- Ollama GPU na porta `11434`.
- Ollama CPU na porta `11435`.
- Ollama router na porta `11436`.
- Open WebUI via portproxy na porta `3000`.
- API Ollama em `/api/tags` via roteador `11436`.
- API Open WebUI em `/api/config`.
- VM Multipass `ia-lab` em estado `Running`.
- Container Docker `open-webui` em `healthy running`.
- Portproxy do Windows.
- Quantidade de processos PX.
- Presenca de processo Ollama.

Relatorios:

```text
C:\IA-LAB\backups\reports
```

O script retorna:

- `exit 0` se status geral for `OK` ou `WARN`.
- `exit 1` se houver `FAIL`.

O healthcheck nao corrige o ambiente; ele apenas diagnostica e registra. A recuperacao automatica fica com `watchdog.ps1`.

## Watchdog

Script:

```powershell
C:\IA-LAB\scripts\maintenance\watchdog.ps1
```

Funcao:

- Se PX estiver indisponivel, chama `startup_px.ps1`.
- Se Ollama estiver indisponivel, chama `startup_ollama.ps1`.
- Se Open WebUI falhar, tenta reiniciar o container `open-webui` dentro da VM.
- Se porta `3000`/portproxy estiver indisponivel, chama `startup_vm.ps1`.

Log:

```text
C:\IA-LAB\scripts\logs
```

## Backups e snapshots

Backup de configuracao:

```powershell
C:\IA-LAB\scripts\maintenance\backup_configs.ps1
```

Destino:

```text
C:\IA-LAB\backups\configs
```

Inclui:

- scripts
- docs
- docker compose
- configuracao VSCode
- export da tarefa `IA-LAB Startup`
- portproxy
- `multipass info`
- `docker inspect open-webui`

Snapshot Multipass:

```powershell
C:\IA-LAB\scripts\maintenance\snapshot_multipass.ps1
```

Politica:

- snapshots automaticos usam prefixo `auto-`
- manter os ultimos 4 snapshots automaticos
- snapshots manuais sem prefixo `auto-` nao sao removidos pelo cleanup

## Git e versionamento

Repositorio remoto:

```text
https://github.com/marcocanedo/ia_lab.git
```

Branch principal:

```text
main
```

Arquivos/pastas locais ignorados:

- `px/`
- `docker/.env`
- `backups/`
- `docker/backups/`
- `scripts/logs/`
- `scripts/archive/legacy/task_backups/`
- caches Python
- segredos e chaves locais

`archive/` contem historico versionavel; nao colocar segredos ou backups grandes ali.

O projeto ja possui commits iniciais publicados no GitHub.

## Estado esperado

Quando tudo esta saudavel:

- `http://127.0.0.1:3000` abre o Open WebUI.
- `http://127.0.0.1:11436/api/tags` lista modelos Ollama.
- `multipass info ia-lab` mostra a VM `Running`.
- `docker inspect open-webui` dentro da VM mostra container `healthy` e `running`.
- `netsh interface portproxy show all` mostra `127.0.0.1:3000` mapeado para o IP atual da VM na porta `3000`.

Modelos observados no roteador em 2026-06-01:

- `qwen2.5:3b`
- `qwen3.5:0.8b`
- `gemma4:31b-cloud`
- `smollm2:135m`
- `llama3.2:3b`
- `gemma3:4b`

## Comandos uteis

Executar manualmente:

```powershell
cd C:\IA-LAB
.\scripts\maintenance\healthcheck.ps1
.\scripts\maintenance\watchdog.ps1
.\scripts\maintenance\backup_configs.ps1
```

Ver portproxy:

```powershell
netsh interface portproxy show all
Test-NetConnection 127.0.0.1 -Port 3000
```

Ver VM:

```powershell
multipass info ia-lab
multipass list
```

Ver Open WebUI dentro da VM:

```powershell
multipass exec ia-lab -- docker ps
multipass exec ia-lab -- docker inspect open-webui
```

## Observacoes importantes para outro GPT

- Nao assumir que o projeto usa Docker Desktop no Windows; Docker roda dentro da VM Multipass.
- Nao trocar o Open WebUI para rodar diretamente no Windows sem motivo forte.
- Nao remover `OLLAMA_BASE_URLS` nem `OLLAMA_BASE_URL`; ambos sao mantidos por compatibilidade.
- Nao apontar Open WebUI diretamente para `11434`; usar o roteador `11436`.
- Nao versionar `docker\.env`, `px\`, backups, logs ou XMLs antigos de `scripts\archive\legacy\task_backups`.
- Scripts agendados devem permanecer silenciosos: Task Scheduler oculto, PowerShell `-NonInteractive` e `-WindowStyle Hidden`.
- Alteracoes nas tarefas reais do Windows exigem PowerShell como Administrador.
- O `healthcheck.ps1` e diagnostico; o `watchdog.ps1` e recuperacao.
- O `startup_vm.ps1` precisa recriar portproxy porque o IP da VM pode mudar.
