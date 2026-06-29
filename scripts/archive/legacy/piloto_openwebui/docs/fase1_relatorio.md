# Relatorio - Fase 1 Open WebUI

## Resultado

Foi aplicada uma configuracao reversivel para expor o Open WebUI em:

```text
http://10.14.0.226:3000
```

sem remover o acesso local atual:

```text
http://localhost:3000
http://127.0.0.1:3000
```

## Estado auditado

```text
Host Windows: 10.14.0.226
Rede local: 10.14.0.0/22
Gateway: 10.14.1.5
VM Multipass ia-lab: 172.21.150.39
Open WebUI na VM: 172.21.150.39:3000
Portproxy existente: 127.0.0.1:3000 -> 172.21.150.39:3000
Firewall: ativo, inbound bloqueado por padrao
Regra existente: OpenWebUI3000 TCP 3000 permitida
Regra criada: IA-LAB OpenWebUI Corporate 3000 TCP 3000 LocalSubnet
PX: 10.14.0.226:18080
Ollama: 10.14.0.226:11434, nao alterado
SSH: nao alterado
```

## Estado aplicado

```text
127.0.0.1:3000   -> 172.21.150.39:3000
10.14.0.226:3000 -> 172.21.150.39:3000
```

## Artefatos criados

```text
network/expose_openwebui_corporate.ps1
network/remove_openwebui_corporate.ps1
docs/piloto/fase1_openwebui.md
docs/piloto/fase1_relatorio.md
```

## Comando de aplicacao executado

Executar em PowerShell como Administrador:

```powershell
.\network\expose_openwebui_corporate.ps1
```

Backup criado em:

```text
logs/network/expose_openwebui_20260529_073616
```

## Comando de rollback

Executar em PowerShell como Administrador:

```powershell
.\network\remove_openwebui_corporate.ps1
```

O rollback remove somente:

```text
10.14.0.226:3000 -> 172.21.150.39:3000
IA-LAB OpenWebUI Corporate 3000
```

## Validacoes locais esperadas

```text
localhost:3000      True
127.0.0.1:3000      True
10.14.0.226:3000    True
172.21.150.39:3000  True
```

Validacao HTTP:

```text
http://127.0.0.1:3000     200 OK
http://10.14.0.226:3000   200 OK
```

## Checklist entre PCs

Em outro PC corporativo:

```powershell
Test-NetConnection 10.14.0.226 -Port 3000
```

No navegador:

```text
http://10.14.0.226:3000
```

Registrar:

```text
PC de origem:
IP de origem:
Data/hora:
Resultado Test-NetConnection:
Resultado navegador:
Usuario testado:
Observacoes:
```

## Pendencias

- Testar a partir de outro PC da rede corporativa.
- Confirmar com TI se o acesso deve ficar restrito a `LocalSubnet` ou a uma lista explicita de IPs.

## Seguranca

- Ollama nao foi exposto pelos scripts.
- SSH nao foi exposto pelos scripts.
- A regra nova limita o acesso de entrada ao perfil `domain,private` e `RemoteIP=LocalSubnet`.
- O Open WebUI deve permanecer com autenticacao habilitada para uso por outros usuarios.
