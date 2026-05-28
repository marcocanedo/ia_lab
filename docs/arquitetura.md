# Arquitetura

## Visao geral

O IA-LAB usa o Windows como host principal e uma VM Ubuntu Multipass para isolar a camada Docker. O Ollama roda no Windows para aproveitar instalacao local e exposicao direta para a rede privada. O Open WebUI roda dentro do Docker na VM e consome o Ollama via IP do host Windows.

```text
Browser -> 127.0.0.1:3000 -> Windows portproxy -> VM ia-lab:3000 -> Docker open-webui:8080 -> Ollama Windows:11434
```

## Dependencias

1. PX deve estar disponivel para downloads corporativos e acesso via proxy NTLM quando necessario.
2. Ollama deve estar ouvindo em `0.0.0.0:11434`.
3. Multipass deve iniciar a VM `ia-lab`.
4. Docker deve estar ativo dentro da VM.
5. Container `open-webui` deve estar `healthy`.
6. Portproxy deve mapear `127.0.0.1:3000` para o IP atual da VM.

## Decisoes tecnicas

- Open WebUI fica na VM para reduzir acoplamento com Windows e preservar compatibilidade Docker.
- Ollama fica no Windows porque os modelos ja estao instalados e validados nessa camada.
- Proxy HTTP foi removido do container Open WebUI para evitar roteamento indevido das chamadas para Ollama.
- `OLLAMA_BASE_URLS` e `OLLAMA_BASE_URL` sao mantidas para compatibilidade entre versoes do Open WebUI.

## Persistencia

- Dados Open WebUI: volume Docker nomeado `open-webui`.
- Scripts: `C:\IA-LAB\scripts`.
- Logs: `C:\IA-LAB\scripts\logs`.
- Backups: `C:\IA-LAB\backups`.
- Compose: `C:\IA-LAB\docker`.
