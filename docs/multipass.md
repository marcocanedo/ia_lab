# Multipass

VM principal:

```text
ia-lab
```

## Validar

```powershell
multipass list
multipass info ia-lab
```

## Networking

A VM recebe IP dinamico na rede Multipass. Nesta etapa, o foco e a provisao da VM e a validacao do acesso via PX. O portproxy do Windows fica para o passo seguinte.

Exemplo:

```text
172.19.230.126
```

## Docker

Docker e operado via:

```powershell
multipass exec ia-lab -- docker ps
```

## Rebuild do zero

Quando a VM antiga for descartada e o conteudo da aplicacao ja estiver preservado em GitHub, reprovisione a camada Multipass com:

```powershell
D:\IA-LAB\scripts\setup\rebuild_multipass_vm.ps1 -DeleteExisting
```

O script:

- recria a VM `ia-lab`
- usa 8 CPUs, 16G de RAM e 120G de disco por padrao
- configura o proxy APT via PX
- executa `apt-get update` dentro da VM
- instala `docker.io`, `docker-compose-v2` e `openssh-server`
- transfere `D:\IA-LAB\docker\docker-compose.yml` e `D:\IA-LAB\docker\.env`
- cria o volume externo `open-webui`
- sobe o `open-webui`
- atualiza o `~/.ssh/config` local para VS Code Remote

Para fazer apenas a etapa inicial desta conversa, sem subir Docker/Open WebUI:

```powershell
D:\IA-LAB\scripts\setup\rebuild_multipass_vm.ps1 -DeleteExisting -BootstrapOnly
```

## Snapshots

```powershell
D:\IA-LAB\scripts\maintenance\snapshot_multipass.ps1
```

Antes de upgrades maiores, criar snapshot manual e validar espaco em disco.
