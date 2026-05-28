# IA-LAB Documentation

Documentacao operacional do laboratorio IA-LAB.

## Componentes

- Windows Host: executa PX, Ollama, VSCode, Browser, Task Scheduler e portproxy.
- PX: proxy NTLM local em `127.0.0.1:18080`.
- Ollama: servidor local em `127.0.0.1:11434`, exposto como `0.0.0.0:11434`.
- Multipass: gerencia a VM Ubuntu `ia-lab`.
- Docker: roda dentro da VM.
- Open WebUI: container Docker `open-webui`, porta `3000`.

## Documentos

- [Arquitetura](arquitetura.md)
- [Fluxo de startup](startup_flow.md)
- [Portas](portas.md)
- [Troubleshooting](troubleshooting.md)
- [Seguranca](seguranca.md)
- [Backup e restore](backup_restore.md)
- [Docker](docker.md)
- [Ollama](ollama.md)
- [Multipass](multipass.md)
- [VSCode](vscode.md)
- [Codex](codex.md)
- [GitHub](github.md)
- [Proxy](proxy.md)
- [Task Scheduler](taskscheduler.md)
- [Roadmap](roadmap.md)
- [Audit Report](audit_report.md)

## Comandos essenciais

```powershell
C:\IA-LAB\scripts\healthcheck.ps1
C:\IA-LAB\scripts\watchdog.ps1
C:\IA-LAB\scripts\backup_configs.ps1
C:\IA-LAB\scripts\configure_vm_proxy.ps1
```

## Estado esperado

- `http://127.0.0.1:3000` abre Open WebUI.
- `http://127.0.0.1:11434/api/tags` lista modelos Ollama.
- `multipass info ia-lab` mostra VM `Running`.
- `docker ps` dentro da VM mostra `open-webui` `healthy`.
