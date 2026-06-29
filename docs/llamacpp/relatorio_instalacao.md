# Relatorio de instalacao llama.cpp

- Atualizado em: 2026-06-01T16:08:49
- Release mais recente consultado: b9459
- Release: b9459
- URL: https://github.com/ggml-org/llama.cpp/releases/tag/b9459
- Executavel: C:\IA-LAB\llama.cpp\releases\b9459\llama-server.exe
- Artefato principal: llama-b9459-bin-win-cuda-12.4-x64.zip
- Runtime CUDA/CUDART: cudart-llama-bin-win-cuda-12.4-x64.zip

## Arquivos baixados
- C:\IA-LAB\llama.cpp\downloads\llama-b9459-bin-win-cuda-12.4-x64.zip - SHA256 AFC164B673EBDCE011C88B735ED3C5A9182EBD5CCD289BC8AF7E4B06D3A36890
- C:\IA-LAB\llama.cpp\downloads\cudart-llama-bin-win-cuda-12.4-x64.zip - SHA256 8C79A9B226DE4B3CACFD1F83D24F962D0773BE79F1E7B75C6AF4DED7E32AE1D6

## Pendencias
- Aplicar `configure_llamacpp_vm_access.ps1` em PowerShell elevado para criar `172.25.112.1:8001-8003 -> 127.0.0.1:8001-8003`.
- Depois da etapa elevada, validar do container: `curl --noproxy "*" http://172.25.112.1:8001/v1/models`.
- Os servidores llama.cpp foram parados ao final para manter o modo manual sob demanda.

## Modelos baixados

- Qwen2.5 7B Instruct Q5_K_M: 2 shards GGUF.
- Qwen2.5 Coder 7B Instruct Q5_K_M: 2 shards GGUF.
- Qwen2.5 14B Instruct Q4_K_M: 3 shards GGUF.
- Total GGUF final: 7 arquivos, aproximadamente 18.51 GB.
- Um GGUF monolitico duplicado do Coder 7B foi removido apos validacao dos shards.

## Open WebUI

- `docker\docker-compose.yml` recebeu `ENABLE_OPENAI_API`, `OPENAI_API_BASE_URLS` e `OPENAI_API_KEYS`.
- `docker\.env` recebeu os endpoints `http://172.25.112.1:8001-8003/v1`.
- O container `open-webui` foi recriado via Compose em `/home/ubuntu/ia-lab-docker`, preservando o volume externo `open-webui`.
- Ollama continuou configurado via `http://10.14.0.226:11436`.

## Testes executados

- Healthcheck geral antes: OK em `C:\IA-LAB\backups\reports\healthcheck_20260601_155052.*`.
- Healthcheck geral depois: OK em `C:\IA-LAB\backups\reports\healthcheck_20260601_163302.*`.
- `Qwen2.5 7B` em `127.0.0.1:8001`: `/v1/models` OK e chat OK.
- `Qwen2.5 Coder 7B` em `127.0.0.1:8002`: `/v1/models` OK e chat OK.
- `Qwen2.5 14B` em `127.0.0.1:8003`: `/v1/models` OK e chat OK com contexto 4096.
- Portas corporativas `10.14.0.226:8001-8003`: fechadas.
- Open WebUI dentro do container acessou Ollama router em `http://10.14.0.226:11436/api/tags`.
