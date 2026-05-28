# IA-LAB Audit Report

Data: 2026-05-27

## Estado validado

- PX responde em `127.0.0.1:18080`.
- Ollama responde em `127.0.0.1:11434`.
- Ollama lista 3 modelos.
- Multipass VM `ia-lab` esta `Running`.
- Docker na VM esta operacional.
- Container `open-webui` esta `running` e `healthy`.
- Open WebUI responde em `http://127.0.0.1:3000/api/config`.
- Portproxy Windows mapeia `127.0.0.1:3000` para a VM.
- Docker Compose foi instalado e `docker compose config` validou o arquivo compose.

## Achados

1. Havia duas instancias PX em execucao. Os scripts novos evitam novas duplicacoes, mas a instancia residual deve ser removida em janela de manutencao.
2. Docker nao existe no PATH do Windows; a operacao Docker correta e via `multipass exec ia-lab -- docker ...`.
3. A VM tinha proxy apt incorreto `172.30.224.1:18080`. Foi corrigido para `172.19.224.1:18080`.
4. O container Open WebUI deve manter `HTTP_PROXY`, `HTTPS_PROXY` e `ALL_PROXY` vazios para nao quebrar comunicacao com Ollama.
5. `OLLAMA_BASE_URLS` e necessario para versoes atuais do Open WebUI; `OLLAMA_BASE_URL` foi mantido por compatibilidade.

## Melhorias implementadas

- Estrutura profissional `docs`, `docker`, `workspace`, `.vscode`, `backups`.
- Healthcheck consolidado.
- Watchdog de recuperacao.
- Backup de configuracoes.
- Cleanup de logs.
- Snapshot Multipass agendavel.
- Docker Compose com volume externo preservando dados atuais.
- Documentacao tecnica e diagramas Mermaid.
- Configuracao VSCode recomendada.
- Configuracao Git/GitHub com proxy PX.
- Tarefas de manutencao no Task Scheduler.

## Pendencias controladas

- Migrar efetivamente o container atual para gerenciamento por Compose em janela de manutencao.
- Fazer snapshot inicial manual apos confirmar politica de retencao e espaco.
- Configurar SSH persistente para VSCode Remote.
- Remover processo PX duplicado sem interromper sessao atual.
