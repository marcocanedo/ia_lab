# Portal IA-LAB

Esta documentacao foi organizada para navegar por tarefa, nao por nome de arquivo.

## Comece aqui

- [Getting started](getting-started.md): visao rapida para entender o laboratorio.
- [Arquitetura](arquitetura.md): como Windows, VM, Docker, Open WebUI e Ollama se conectam.
- [Portas](portas.md): mapa de portas e portproxy.
- [Diagramas](diagrams/arquitetura.mmd): fluxo visual em Mermaid.

## Operar

- [Operacao diaria](operacao.md): comandos mais usados e estado esperado.
- [Startup flow](startup_flow.md): ordem de inicializacao.
- [Task Scheduler](taskscheduler.md): tarefas esperadas e como recriar.
- [Ollama](ollama.md): backends GPU/CPU e roteador.
- [llama.cpp](llamacpp/README.md): backend GGUF sob demanda.

## Corrigir problemas

- [Troubleshooting](troubleshooting.md): sintomas comuns e correcoes.
- [Proxy](proxy.md): PX e proxy APT da VM.
- [Multipass](multipass.md): VM `ia-lab`.
- [Docker](docker.md): Open WebUI dentro da VM.
- [Rebuild da VM](multipass.md): reprovisionamento limpo da camada Multipass.

## Manter e restaurar

- [Manutencao](manutencao.md): healthcheck, watchdog, backups e limpeza.
- [Backup e restore](backup_restore.md): restauracao e snapshots.
- [Seguranca](seguranca.md): limites de exposicao e boas praticas.
- [Scripts e estrutura](scripts.md): onde ficam os scripts apos a reorganizacao.

## Apoio ao desenvolvimento

- [VS Code](vscode.md)
- [Codex](codex.md)
- [GitHub](github.md)
- [Roadmap](roadmap.md)
- [Audit report](audit_report.md)
