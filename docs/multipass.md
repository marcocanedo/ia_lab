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

A VM recebe IP dinamico na rede Multipass. O script `startup_vm.ps1` detecta o IP a cada execucao e recria o portproxy Windows.

Exemplo:

```text
172.19.230.126
```

## Docker

Docker e operado via:

```powershell
multipass exec ia-lab -- docker ps
```

## Snapshots

```powershell
C:\IA-LAB\scripts\maintenance\snapshot_multipass.ps1
```

Antes de upgrades maiores, criar snapshot manual e validar espaco em disco.
