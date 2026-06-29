# Fase 1 - Open WebUI na rede corporativa

## Objetivo

Expor o Open WebUI que roda na VM Multipass `ia-lab` para outros computadores da rede corporativa em:

```text
http://10.14.0.226:3000
```

O acesso local existente deve continuar funcionando:

```text
http://localhost:3000
http://127.0.0.1:3000
```

## Topologia validada

```text
PC corporativo -> 10.14.0.226:3000 -> portproxy Windows -> 172.21.150.39:3000 -> Open WebUI Docker
```

Estado base:

```text
Windows host: 10.14.0.226
Multipass VM ia-lab: 172.21.150.39
Open WebUI: 172.21.150.39:3000
Portproxy local atual: 127.0.0.1:3000 -> 172.21.150.39:3000
Ollama router: 172.21.144.1:11436 a partir da VM -> roteia para 11434 GPU ou 11435 CPU por modelo
SSH: porta 22 da VM, nao exposta pelo script
```

## Scripts

Expor para a rede corporativa:

```powershell
.\network\expose_openwebui_corporate.ps1
```

Rollback:

```powershell
.\network\remove_openwebui_corporate.ps1
```

Ambos devem ser executados em PowerShell como Administrador.

## O que o script de exposicao faz

- Salva backup de `portproxy`, firewall, `ipconfig` e `netstat` em `logs\network`.
- Valida que a VM responde em `172.21.150.39:3000`.
- Preserva o portproxy local `127.0.0.1:3000`.
- Adiciona o portproxy corporativo `10.14.0.226:3000 -> 172.21.150.39:3000`.
- Cria a regra `IA-LAB OpenWebUI Corporate 3000` para TCP 3000, restrita a `LocalSubnet`.
- Valida `localhost`, `127.0.0.1`, `10.14.0.226` e a VM.

## O que o rollback faz

- Salva backup antes da remocao.
- Remove somente o portproxy `10.14.0.226:3000`.
- Remove somente a regra `IA-LAB OpenWebUI Corporate 3000`.
- Preserva o acesso local em `127.0.0.1:3000`.
- Nao altera Ollama, SSH, Docker ou Multipass.

## Checklist de teste entre PCs

Executar em outro computador da mesma rede corporativa:

```powershell
Test-NetConnection 10.14.0.226 -Port 3000
```

Resultado esperado:

```text
TcpTestSucceeded : True
```

Abrir no navegador do outro computador:

```text
http://10.14.0.226:3000
```

Validar:

- A tela do Open WebUI abre.
- Login/autenticacao funcionam.
- Uma conversa simples funciona.
- A pagina continua acessivel localmente no host em `http://127.0.0.1:3000`.
- `http://10.14.0.226:11434` nao deve ser divulgado nem usado por usuarios.
- SSH da VM nao deve ser publicado para usuarios.

## Riscos e controles

- A porta 3000 passa a aceitar conexoes da sub-rede local.
- O Open WebUI deve ter autenticacao habilitada antes de uso por terceiros.
- A regra criada pelo script usa `RemoteIP=LocalSubnet`; para liberar outras VLANs, a regra deve ser revisada com a equipe de rede.
- SSH nao e alterado pelos scripts. O Open WebUI usa somente o roteador Ollama na porta 11436.
- O Open WebUI usa `OLLAMA_BASE_URL=http://172.21.144.1:11436`; esse e o gateway do Default Switch visto pela VM Multipass.
- Se houver bloqueio por ACL de rede, GPO ou segmentacao entre VLANs, o teste entre PCs pode falhar mesmo com o host configurado corretamente.
