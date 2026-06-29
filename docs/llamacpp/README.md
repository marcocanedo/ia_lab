# llama.cpp no IA-LAB

`llama.cpp` foi adicionado como backend local complementar ao Ollama. Ele roda no Windows Host, usa modelos GGUF em disco local e expoe API OpenAI-compatible por modelo.

## Arquitetura

- Windows Host: executa `llama-server.exe`, modelos GGUF e logs.
- Open WebUI: continua no container `open-webui` dentro da VM Multipass `ia-lab`.
- Ollama: continua preservado no roteador `http://10.14.0.226:11436`.
- llama.cpp local: `127.0.0.1:8001-8003`.
- Acesso do Open WebUI ao host: `http://172.25.112.1:8001-8003/v1`, via portproxy restrito ao Default Switch.

As portas `8001`, `8002` e `8003` nao devem ser abertas em `10.14.0.226` nem divulgadas para outros computadores.

## Portas

| Porta | Modelo | API |
| ---: | --- | --- |
| 8001 | Qwen2.5 7B Instruct Q5_K_M | `http://127.0.0.1:8001/v1` |
| 8002 | Qwen2.5 Coder 7B Instruct Q5_K_M | `http://127.0.0.1:8002/v1` |
| 8003 | Qwen2.5 14B Instruct Q4_K_M | `http://127.0.0.1:8003/v1` |

## Diretorios

- Binarios: `C:\IA-LAB\llama.cpp`
- Modelos: `C:\IA-LAB\models\gguf`
- Scripts: `C:\IA-LAB\scripts\llamacpp`
- Logs: `C:\IA-LAB\scripts\logs\llamacpp`
- Documentacao: `C:\IA-LAB\docs\llamacpp`

## Uso

Instalar binario oficial CUDA:

```powershell
C:\IA-LAB\scripts\llamacpp\install_llamacpp.ps1
```

Baixar modelos:

```powershell
C:\IA-LAB\scripts\llamacpp\download_models.ps1
```

Iniciar os dois modelos 7B:

```powershell
C:\IA-LAB\scripts\llamacpp\start_all_llamacpp.ps1
```

Iniciar tambem o 14B:

```powershell
C:\IA-LAB\scripts\llamacpp\start_all_llamacpp.ps1 -Include14B
```

Parar processos iniciados pelos scripts:

```powershell
C:\IA-LAB\scripts\llamacpp\stop_all_llamacpp.ps1
```

Healthcheck:

```powershell
C:\IA-LAB\scripts\llamacpp\healthcheck_llamacpp.ps1
```

## Open WebUI

O Compose recebeu `ENABLE_OPENAI_API`, `OPENAI_API_BASE_URLS` e `OPENAI_API_KEYS`, preservando `ENABLE_OLLAMA_API`, `OLLAMA_BASE_URLS` e `OLLAMA_BASE_URL`.

Para permitir que o container alcance o Windows sem expor a rede corporativa, aplicar em PowerShell elevado:

```powershell
C:\IA-LAB\scripts\llamacpp\configure_llamacpp_vm_access.ps1
```

Depois, aplicar a configuracao do Compose:

```powershell
C:\IA-LAB\scripts\llamacpp\configure_openwebui_llamacpp.ps1
```

Se o Open WebUI ignorar as variaveis por configuracao persistida no banco, configurar manualmente em `Admin Panel > Settings > Connections > OpenAI API`.
