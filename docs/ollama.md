# Ollama

Ollama roda no Windows Host com dois backends e um roteador local.

## Configuracao

Variavel persistida para o backend GPU:

```text
OLLAMA_HOST=0.0.0.0:11434
```

O `startup_ollama.ps1` tambem inicia:

- backend GPU em `0.0.0.0:11434`;
- backend CPU em `0.0.0.0:11435`, com `OLLAMA_LLM_LIBRARY=cpu_avx2`;
- roteador em `0.0.0.0:11436`.

O Open WebUI deve usar o roteador, nao um backend direto:

```text
OLLAMA_BASE_URL=http://10.14.0.226:11436
OLLAMA_BASE_URLS=http://10.14.0.226:11436
```

## Roteamento por modelo

- CPU: `gemma3:4b`, `qwen2.5:3b`.
- GPU: `smollm2:135m`, `llama3.2:3b`, `qwen3.5:0.8b`.
- Default: GPU.

## Validacao

```powershell
Test-NetConnection 127.0.0.1 -Port 11434
Test-NetConnection 127.0.0.1 -Port 11435
Test-NetConnection 127.0.0.1 -Port 11436
Invoke-RestMethod http://127.0.0.1:11436/api/tags
```

Dentro do container:

```powershell
multipass exec ia-lab -- docker exec open-webui curl --noproxy "*" http://10.14.0.226:11436/api/tags
```

## Modelos observados

- `qwen2.5:3b`
- `qwen3.5:0.8b`
- `gemma4:31b-cloud`
- `smollm2:135m`
- `llama3.2:3b`
- `gemma3:4b`

## Recuperacao

```powershell
C:\IA-LAB\scripts\startup\startup_ollama.ps1
```
