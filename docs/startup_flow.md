# Startup Flow

## Tarefa principal

Task Scheduler:

```text
IA-LAB Startup
```

Acao:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "C:\IA-LAB\scripts\startup_apps.ps1"
```

Gatilhos:

- boot do Windows, atraso 30 segundos
- logon do usuario, atraso 30 segundos

## Ordem

1. `startup_px.ps1`
2. `startup_ollama.ps1`
3. `startup_vm.ps1`

## Controles implementados

- Scripts idempotentes.
- Validacao de porta antes de seguir.
- Timeouts e retries.
- Log via transcript em `scripts\logs`.
- Tarefas antigas desabilitadas para evitar execucao concorrente.

## Race conditions mitigadas

- VM pode mudar de IP a cada boot: `startup_vm.ps1` detecta IP e recria portproxy.
- Ollama pode demorar para abrir porta: script aguarda ate 60 segundos.
- Open WebUI pode demorar a responder: script aguarda porta 3000.
- Duplo gatilho boot/logon nao duplica processos porque os scripts verificam portas/processos.
