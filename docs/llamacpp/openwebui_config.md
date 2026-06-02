# Open WebUI com llama.cpp

O Ollama continua ativo no Open WebUI via:

```text
OLLAMA_BASE_URLS=http://10.14.0.226:11436
OLLAMA_BASE_URL=http://10.14.0.226:11436
```

Os endpoints OpenAI-compatible do llama.cpp foram adicionados no `docker\.env`:

```text
OPENAI_API_BASE_URLS=http://172.25.112.1:8001/v1;http://172.25.112.1:8002/v1;http://172.25.112.1:8003/v1
OPENAI_API_KEYS=dummy-key;dummy-key;dummy-key
```

## Aplicar

1. Inicie os modelos desejados no Windows Host.
2. Em PowerShell elevado, aplique o acesso VM:

```powershell
C:\IA-LAB\scripts\llamacpp\configure_llamacpp_vm_access.ps1
```

3. Aplique o Compose do Open WebUI:

```powershell
C:\IA-LAB\scripts\llamacpp\configure_openwebui_llamacpp.ps1
```

## Alternativa manual

Se as variaveis forem ignoradas por configuracao persistida do Open WebUI, use:

`Admin Panel > Settings > Connections > OpenAI API > Add Connection`

Adicionar:

- `http://172.25.112.1:8001/v1` com API key `dummy-key`.
- `http://172.25.112.1:8002/v1` com API key `dummy-key`.
- `http://172.25.112.1:8003/v1` com API key `dummy-key`.

Model IDs esperados:

- `qwen2.5-7b-instruct-gguf-q5_k_m`
- `qwen2.5-coder-7b-instruct-gguf-q5_k_m`
- `qwen2.5-14b-instruct-gguf-q4_k_m`
