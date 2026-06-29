# Portas

| Porta | Camada | Servico | Uso |
| --- | --- | --- | --- |
| 18080 | Windows | PX | Proxy NTLM local |
| 11434 | Windows | Ollama GPU | Backend GPU |
| 11435 | Windows | Ollama CPU | Backend CPU `cpu_avx2` |
| 11436 | Windows | Ollama Router | Endpoint usado pelo Open WebUI |
| 3000 | Windows | Portproxy | Entrada local do Open WebUI |
| 3000 | VM | Docker publish | Porta host da VM para Open WebUI |
| 8080 | Container | Open WebUI | Porta interna do app |

## Portproxy

Estado local validado em 2026-06-01:

```text
127.0.0.1:3000 -> 172.25.122.220:3000
```

Pendencia operacional: existe um portproxy corporativo antigo `10.14.0.226:3000 -> 172.21.150.39:3000`, apontando para IP anterior da VM. Ele deve ser revisado em janela controlada se o acesso corporativo ao Open WebUI for reativado.

Validar:

```powershell
netsh interface portproxy show all
Test-NetConnection 127.0.0.1 -Port 3000
Test-NetConnection 127.0.0.1 -Port 11436
```

## Firewall

O acesso local usa loopback. Para acesso externo, revisar regras de firewall Windows e exposicao da VM antes de abrir portas. Por padrao, o recomendado e manter acesso local apenas.
