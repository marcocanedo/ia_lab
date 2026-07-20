# IA-LAB

Laboratorio de infraestrutura base em Windows com PX, Multipass, uma VM Ubuntu `ia-lab` e scripts de suporte.

## Comece aqui

- [Portal da documentacao](docs/index.md)
- [Operacao diaria](docs/operacao.md)
- [Troubleshooting](docs/troubleshooting.md)
- [Arquitetura](docs/arquitetura.md)

## Acesso rapido

| Componente | Endereco |
| --- | --- |
| PX | <http://127.0.0.1:18080> |
| VM Multipass | `multipass list` / `multipass info ia-lab` |
| SSH na VM | IP atual da VM, porta `22` |

## Comandos essenciais

```powershell
cd D:\IA-LAB
.\scripts\startup\startup_vm.ps1
.\scripts\startup\startup_apps.ps1
.\scripts\maintenance\healthcheck.ps1
.\scripts\maintenance\watchdog.ps1
```

## Estrutura

- `scripts\startup`: boot do PX, Multipass e VM.
- `scripts\maintenance`: healthcheck, watchdog e limpeza de logs.
- `scripts\setup`: configuracao de Task Scheduler, proxy e reconstruicao da VM.
- `scripts\tools`: inventario e ferramentas auxiliares.
- `docs`: portal navegavel e guias tecnicos.
- `archive`: artefatos historicos preservados fora da operacao diaria.

## Agendamento

As tarefas principais sao:

```text
IA-LAB VM Boot       -> scripts\startup\startup_vm.ps1 (SYSTEM, no boot)
IA-LAB Host Services -> scripts\startup\startup_apps.ps1 (usuario, no logon)
```

Depois de reorganizar ou restaurar o projeto, recrie as tarefas em PowerShell como Administrador:

```powershell
D:\IA-LAB\scripts\setup\configure_startup_tasks.ps1
D:\IA-LAB\scripts\setup\configure_maintenance_tasks.ps1
```
