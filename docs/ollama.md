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
- GPU: `smollm2:135m`, `llama3.2:3b`, `qwen3.5:0.8b`, `gemma4:12b-gpu`.
- Default: GPU.

## Gemma 4 12B

Modelo recomendado para esta workstation:

```text
gemma4:12b-gpu
```

Esse alias usa `gemma4:12b-it-q4_K_M` com contexto controlado para chat geral:

- `num_ctx 8192`
- `temperature 1.0`
- `top_p 0.95`
- `top_k 64`

A variante `gemma4:12b-it-q8_0` nao e recomendada para a RTX A2000 12GB porque o modelo tem cerca de 13 GB antes do uso adicional de KV cache.

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
- `gemma4:12b-gpu`
- `gemma4:12b-it-q4_K_M`
- `smollm2:135m`
- `llama3.2:3b`
- `gemma3:4b`

## Recuperacao

```powershell
D:\IA-LAB\scripts\startup\startup_ollama.ps1
```
