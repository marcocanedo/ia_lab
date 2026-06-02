# Startup Flow

## Tarefa principal

Task Scheduler:

```text
IA-LAB Startup
```

Acao:

```powershell
powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -WindowStyle Hidden -File "C:\IA-LAB\scripts\startup\startup_apps.ps1"
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
- Execucao silenciosa via Task Scheduler oculto e PowerShell `-WindowStyle Hidden`.
- Tarefas antigas desabilitadas para evitar execucao concorrente.

## Race conditions mitigadas

- VM pode mudar de IP a cada boot: `startup_vm.ps1` detecta IP e recria portproxy.
- Ollama pode demorar para abrir portas: script aguarda ate 60 segundos pelos backends `11434`/`11435` e pelo roteador `11436`.
- Open WebUI pode demorar a responder: script aguarda porta 3000.
- Duplo gatilho boot/logon nao duplica processos porque os scripts verificam portas/processos.

## Ollama

`startup_ollama.ps1` configura proxy PX para downloads, inicia o backend GPU em `11434`, o backend CPU em `11435` e o `ollama_router.ps1` em `11436`. O Open WebUI deve consumir somente o roteador.
