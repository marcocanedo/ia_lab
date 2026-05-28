# Portas

| Porta | Camada | Servico | Uso |
| --- | --- | --- | --- |
| 18080 | Windows | PX | Proxy NTLM local |
| 11434 | Windows | Ollama | API Ollama |
| 3000 | Windows | Portproxy | Entrada local do Open WebUI |
| 3000 | VM | Docker publish | Porta host da VM para Open WebUI |
| 8080 | Container | Open WebUI | Porta interna do app |

## Portproxy

Exemplo esperado:

```text
127.0.0.1:3000 -> 172.19.230.126:3000
```

Validar:

```powershell
netsh interface portproxy show all
Test-NetConnection 127.0.0.1 -Port 3000
```

## Firewall

O acesso local usa loopback. Para acesso externo, revisar regras de firewall Windows e exposicao da VM antes de abrir portas. Por padrao, o recomendado e manter acesso local apenas.
