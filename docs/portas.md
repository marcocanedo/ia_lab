# Portas

| Porta | Camada | Servico | Uso |
| --- | --- | --- | --- |
| 18080 | Windows | PX | Proxy NTLM local |
| 22 | VM | SSH | Acesso remoto na VM `ia-lab` |

## Observacoes

- A porta `18080` deve continuar acessivel apenas no host local.
- A VM `ia-lab` usa IP dinamico; o acesso SSH e feito no IP atual da instância.
- Nao ha portas publicas de IA no caminho ativo.

## Validar

```powershell
Test-NetConnection 127.0.0.1 -Port 18080
multipass info ia-lab
```
