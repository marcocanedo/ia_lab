# Ollama

Ollama roda no Windows Host.

## Configuracao

Variavel:

```text
OLLAMA_HOST=0.0.0.0:11434
```

Isso permite que a VM acesse o Ollama pelo IP do Windows.

## Validacao

```powershell
Test-NetConnection 127.0.0.1 -Port 11434
Invoke-RestMethod http://127.0.0.1:11434/api/tags
```

Dentro do container:

```powershell
multipass exec ia-lab -- docker exec open-webui curl --noproxy "*" http://10.14.0.226:11434/api/tags
```

## Modelos observados

- `gemma4:e4b`
- `llama3.2:3b`
- `gemma3:4b`

## Recuperacao

```powershell
C:\IA-LAB\scripts\startup_ollama.ps1
```
