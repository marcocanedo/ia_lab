# Backup e Restore

## Backups implementados

Script:

```powershell
C:\IA-LAB\scripts\maintenance\backup_configs.ps1
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

Destino:

```text
C:\IA-LAB\backups\configs
```

## Snapshot Multipass

Script:

```powershell
C:\IA-LAB\scripts\maintenance\snapshot_multipass.ps1
```

Cria snapshot da VM `ia-lab`.

Politica definida:

- snapshots automaticos usam prefixo `auto-`
- reter os ultimos 4 snapshots automaticos
- snapshots manuais sem prefixo `auto-` nao sao removidos pelo cleanup

Cleanup:

```powershell
C:\IA-LAB\scripts\maintenance\cleanup_multipass_snapshots.ps1
```

## Restore resumido

1. Restaurar `C:\IA-LAB\scripts`.
2. Restaurar tarefa `IA-LAB Startup` ou executar `configure_startup_tasks.ps1`.
3. Restaurar portproxy via `startup_vm.ps1`.
4. Confirmar VM `ia-lab`.
5. Confirmar volume Docker `open-webui`.
6. Rodar `healthcheck.ps1`.

## Backup do volume Docker

Dentro da VM:

```bash
docker run --rm -v open-webui:/data -v "$PWD:/backup" alpine \
  tar czf /backup/open-webui-data.tgz -C /data .
```
