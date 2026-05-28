# Proxy

PX roda no Windows Host em:

```text
127.0.0.1:18080
```

## Uso

O PX resolve cenarios com proxy NTLM corporativo. Ele deve estar ativo antes de operacoes que precisam baixar dependencias em redes restritas.

## Open WebUI

O container Open WebUI nao deve usar `HTTP_PROXY` para falar com Ollama. A configuracao atual deixa essas variaveis vazias dentro do container e usa `NO_PROXY`.

## Proxy da VM Multipass

Problema encontrado: a VM estava com apt apontando para `172.30.224.1:18080`, endereco inacessivel a partir da rede Multipass.

Correcao aplicada:

```text
Acquire::http::Proxy "http://172.19.224.1:18080";
Acquire::https::Proxy "http://172.19.224.1:18080";
```

Arquivo na VM:

```text
/etc/apt/apt.conf.d/95proxy
```

Script:

```powershell
C:\IA-LAB\scripts\configure_vm_proxy.ps1
```

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
