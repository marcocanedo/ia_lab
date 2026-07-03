# Operacao diaria

## Comandos principais

```powershell
cd D:\IA-LAB
.\scripts\maintenance\healthcheck.ps1
.\scripts\maintenance\watchdog.ps1
```

## Estado esperado

- PX responde em <http://127.0.0.1:18080>.
- Multipass esta disponivel.
- VM `ia-lab` esta `Running`.
- SSH na VM responde no IP atual.
- `~\.ssh\config` aponta para a VM atual.

## Inicializacao manual

```powershell
D:\IA-LAB\scripts\startup\startup_vm.ps1
D:\IA-LAB\scripts\startup\startup_apps.ps1
```

Ordem executada:

1. Multipass e VM `ia-lab`.
2. PX.
3. Revalidacao da VM e sincronizacao SSH no logon do usuario.

## Proximos links

- [Startup flow](startup_flow.md)
- [Task Scheduler](taskscheduler.md)
- [Manutencao](manutencao.md)
