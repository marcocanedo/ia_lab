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

A VM recebe IP dinamico na rede Multipass. O acesso remoto e feito pelo IP atual via SSH.

## Rebuild do zero

Quando a VM antiga for descartada, reprovisione a camada Multipass com:

```powershell
D:\IA-LAB\scripts\setup\rebuild_multipass_vm.ps1 -DeleteExisting
```

O script:

- recria a VM `ia-lab`
- usa 8 CPUs, 16G de RAM e 120G de disco por padrao
- inicia o PX se necessario antes do `apt-get update`
- cria a VM Ubuntu com `openssh-server`
- configura o proxy APT via PX
- executa `apt-get update` dentro da VM
- sincroniza a configuracao SSH do usuario

Para fazer apenas a etapa inicial, sem atualizar a configuracao SSH local:

```powershell
D:\IA-LAB\scripts\setup\rebuild_multipass_vm.ps1 -DeleteExisting -BootstrapOnly
```

## SSH

Depois de criar ou recriar a VM, rode:

```powershell
D:\IA-LAB\scripts\startup\update_ssh_config.ps1
```

Isso atualiza `~\.ssh\config` e injeta a chave publica na VM.
