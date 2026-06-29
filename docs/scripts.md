# Scripts e estrutura

Os scripts foram separados por funcao para reduzir acoplamento visual e facilitar manutencao.

## `scripts\startup`

Inicializacao do laboratorio:

- `startup_apps.ps1`
- `startup_px.ps1`
- `startup_ollama.ps1`
- `startup_vm.ps1`
- `ollama_router.ps1`
- `update_ssh_config.ps1`

## `scripts\maintenance`

Operacao recorrente:

- `healthcheck.ps1`
- `watchdog.ps1`
- `backup_configs.ps1`
- `snapshot_multipass.ps1`
- `cleanup_multipass_snapshots.ps1`
- `cleanup_logs.ps1`

## `scripts\setup`

Configuracao do host:

- `configure_startup_tasks.ps1`
- `configure_maintenance_tasks.ps1`
- `configure_vm_proxy.ps1`
- `configure_ollama_router_firewall.ps1`
- `git_setup.ps1`
- `apt_95proxy`

## `scripts\tools`

Ferramentas auxiliares e migracao:

- `gerar_inventario_migracao.ps1`
- `gerar_top_consumos.ps1`
- `fase7b_manifesto_backup.ps1`

## Subdominios

- `scripts\network`: exposicao e rollback controlados do Open WebUI.
- `scripts\llamacpp`: instalacao, modelos, start/stop e healthcheck do llama.cpp.
- `scripts\archive`: legado preservado de reorganizacoes anteriores.
