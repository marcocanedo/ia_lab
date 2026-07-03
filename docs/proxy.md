# Proxy

## PX

O PX roda no Windows Host em:

```text
127.0.0.1:18080
```

Ele deve estar ativo antes de operacoes que precisam baixar dependencias em redes restritas.

## Proxy da VM Multipass

O script `configure_vm_proxy.ps1` escreve o proxy APT dentro da VM `ia-lab` usando o gateway correto da rede Multipass.

Arquivo aplicado na VM:

```text
/etc/apt/apt.conf.d/95proxy
```

Script:

```powershell
D:\IA-LAB\scripts\setup\configure_vm_proxy.ps1
```

Use `-Preview` para inspecionar o valor antes de aplicar.

## Git

Se necessario:

```powershell
git config --global http.proxy http://127.0.0.1:18080
git config --global https.proxy http://127.0.0.1:18080
```

Para remover:

```powershell
git config --global --unset http.proxy
git config --global --unset https.proxy
```
