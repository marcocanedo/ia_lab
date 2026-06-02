# IA-LAB

Laboratorio local de IA em Windows com PX, Ollama, Multipass, Docker, Open WebUI e llama.cpp.

## Comece aqui

- [Portal da documentacao](docs/index.md)
- [Operacao diaria](docs/operacao.md)
- [Troubleshooting](docs/troubleshooting.md)
- [Arquitetura](docs/arquitetura.md)
- [Backup e restore](docs/backup_restore.md)

## Acesso rapido

| Servico | URL |
| --- | --- |
| Open WebUI | <http://127.0.0.1:3000> |
| Ollama router | <http://127.0.0.1:11436> |
| llama.cpp 7B | <http://127.0.0.1:8001/v1> |
| llama.cpp coder | <http://127.0.0.1:8002/v1> |
| llama.cpp 14B | <http://127.0.0.1:8003/v1> |
| PX | <http://127.0.0.1:18080> |

## Comandos essenciais

```powershell
cd C:\IA-LAB
.\scripts\maintenance\healthcheck.ps1
.\scripts\maintenance\watchdog.ps1
.\scripts\maintenance\backup_configs.ps1
```

## Estrutura

- `scripts\startup`: inicializacao do PX, Ollama, VM e Open WebUI.
- `scripts\maintenance`: healthcheck, watchdog, backup, snapshots e limpeza.
- `scripts\setup`: configuracao de Task Scheduler, proxy, firewall e Git.
- `scripts\tools`: inventario, manifestos e ferramentas auxiliares.
- `docs`: portal navegavel e guias tecnicos.
- `archive`: artefatos historicos preservados fora da operacao diaria.

## Agendamento

A tarefa principal esperada e `IA-LAB Startup`, apontando para:

```text
C:\IA-LAB\scripts\startup\startup_apps.ps1
```

Depois de reorganizar ou restaurar o projeto, recrie as tarefas em PowerShell como Administrador:

```powershell
C:\IA-LAB\scripts\setup\configure_startup_tasks.ps1
C:\IA-LAB\scripts\setup\configure_maintenance_tasks.ps1
```
