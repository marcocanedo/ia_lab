# Startup Flow

## Tarefas principais

Task Scheduler:

```text
IA-LAB VM Boot
IA-LAB Host Services
```

Acoes:

```powershell
powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -WindowStyle Hidden -File "D:\IA-LAB\scripts\startup\startup_vm.ps1"
powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -WindowStyle Hidden -File "D:\IA-LAB\scripts\startup\startup_apps.ps1"
```

Gatilhos:

- boot do Windows, atraso 30 segundos: `IA-LAB VM Boot`
- logon do usuario, atraso 20 segundos: `IA-LAB Host Services`

## Ordem

1. `startup_vm.ps1` no boot do host.
2. `startup_px.ps1` no logon do usuario.
3. `startup_vm.ps1` novamente no logon para sincronizar SSH e confirmar a VM.

## Controles implementados

- Scripts idempotentes.
- Validacao de porta antes de seguir.
- Timeouts e retries.
- Log via transcript em `scripts\logs`.
- Execucao silenciosa via Task Scheduler oculto e PowerShell `-WindowStyle Hidden`.
- Tarefas antigas desabilitadas para evitar execucao concorrente.

## Race conditions mitigadas

- VM pode mudar de IP a cada boot: `startup_vm.ps1` detecta o IP e `update_ssh_config.ps1` sincroniza o acesso.
- PX pode demorar para abrir a porta `18080`: o script aguarda antes de seguir.
- Duplo gatilho boot/logon nao duplica processos porque os scripts verificam estado antes de agir.
