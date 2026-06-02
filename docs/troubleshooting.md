# Troubleshooting

## Open WebUI retorna 500

Sintoma observado:

```text
500: Internal Error
```

Causas provaveis:

- Open WebUI usando URL antiga do Ollama persistida.
- Variavel incorreta ou incompleta para endpoint Ollama.
- Proxy HTTP dentro do container interferindo com chamadas para `10.14.0.226:11436`.

Correcao aplicada:

```bash
docker rm -f open-webui
docker run -d \
  --name open-webui \
  --restart unless-stopped \
  -p 3000:8080 \
  -e ENABLE_OLLAMA_API=true \
  -e OLLAMA_BASE_URLS=http://10.14.0.226:11436 \
  -e OLLAMA_BASE_URL=http://10.14.0.226:11436 \
  -e NO_PROXY=localhost,127.0.0.1,10.14.0.226,172.30.224.1,172.30.0.0/16 \
  -e HTTP_PROXY= \
  -e HTTPS_PROXY= \
  -e ALL_PROXY= \
  -v open-webui:/app/backend/data \
  ghcr.io/open-webui/open-webui:main
```

Validar:

```powershell
multipass exec ia-lab -- docker logs open-webui --tail 120
multipass exec ia-lab -- docker exec open-webui curl --noproxy "*" http://10.14.0.226:11436/api/tags
```

## Docker inacessivel no Windows

Docker roda dentro da VM, nao no host Windows. Use:

```powershell
multipass exec ia-lab -- docker ps
```

## Ollama nao aparece no Open WebUI

Validar no Windows:

```powershell
Test-NetConnection 127.0.0.1 -Port 11434
Test-NetConnection 127.0.0.1 -Port 11435
Test-NetConnection 127.0.0.1 -Port 11436
Invoke-RestMethod http://127.0.0.1:11436/api/tags
```

Validar dentro do container:

```powershell
multipass exec ia-lab -- docker exec open-webui curl --noproxy "*" http://10.14.0.226:11436/api/tags
```

## Roteador Ollama indisponivel

Se `11434` e `11435` responderem, mas `11436` falhar, reiniciar apenas o startup do Ollama:

```powershell
C:\IA-LAB\scripts\startup\startup_ollama.ps1
```

Validar logs:

```powershell
Get-Content C:\IA-LAB\scripts\logs\ollama_router.err.log -Tail 80
Get-Content C:\IA-LAB\scripts\logs\ollama_router.out.log -Tail 80
```

## VSCode Remote SSH

Se SSH falhar:

- confirmar IP da VM com `multipass info ia-lab`
- confirmar `openssh-server` na VM
- testar `ssh ubuntu@<ip-da-vm>`
- revisar `~/.ssh/config`

## GitHub atras do proxy

Usar HTTPS com Git Credential Manager. Se a rede exigir proxy:

```powershell
git config --global http.proxy http://127.0.0.1:18080
git config --global https.proxy http://127.0.0.1:18080
```

Se falhar autenticacao, limpar credenciais antigas no Windows Credential Manager.
