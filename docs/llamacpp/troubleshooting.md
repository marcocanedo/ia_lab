# Troubleshooting llama.cpp

## Porta ocupada

Os scripts recusam iniciar se `127.0.0.1:8001-8003` ja estiverem em uso.

```powershell
Get-NetTCPConnection -LocalPort 8001,8002,8003 -ErrorAction SilentlyContinue
```

## Modelo nao carrega

Verifique se os arquivos GGUF existem:

```powershell
C:\IA-LAB\scripts\llamacpp\healthcheck_llamacpp.ps1
```

Consulte logs em `C:\IA-LAB\scripts\logs\llamacpp`.

## Falta de VRAM ou CUDA

Todos os servidores usam `-ngl 999` para tentar offload maximo em GPU. Se falhar por memoria:

- inicie apenas um modelo por vez;
- comece pelos 7B;
- no 14B, mantenha `-Context 4096`;
- reduza contexto antes de reduzir camadas GPU.

Use:

```powershell
nvidia-smi
```

## Fallback CPU

Se o binario CUDA nao carregar GPU, o llama.cpp pode cair para CPU ou falhar conforme o release. Registre o comportamento em `relatorio_instalacao.md` e nao altere Ollama para compensar.

## Open WebUI nao enxerga endpoint

Valide do Windows:

```powershell
Invoke-RestMethod http://127.0.0.1:8001/v1/models
```

Valide de dentro do container:

```powershell
multipass exec ia-lab -- docker exec open-webui curl --noproxy "*" http://172.25.112.1:8001/v1/models
```

Se falhar do container, rode `configure_llamacpp_vm_access.ps1` em PowerShell elevado.

## Proxy interferindo

O container Open WebUI deve manter `HTTP_PROXY`, `HTTPS_PROXY` e `ALL_PROXY` vazios. O `NO_PROXY` deve conter `172.25.112.1` e a rede `172.25.112.0/20`.

## Firewall

A regra esperada e restrita a:

- `LocalIP=172.25.112.1`
- `LocalPort=8001-8003`
- `RemoteIP=172.25.112.0/20`
- perfis `Domain,Private`

Nao criar regra para `10.14.0.226:8001-8003` sem autorizacao explicita.
