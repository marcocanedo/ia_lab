# Troubleshooting

## `opencode` nao encontrado no terminal

Se a instalacao do `opencode` funcionou, mas o comando nao abre de qualquer pasta no Windows:

- confirmar que `%APPDATA%\npm` esta no `PATH` do usuario
- reiniciar o terminal depois de alterar o `PATH`
- usar o comando `opencode`, nao `opencod`

Validar:

```powershell
Get-Command opencode
$env:Path -split ';' | Where-Object { $_ -ieq "$env:APPDATA\npm" }
```

## PX nao responde

Validar:

```powershell
Test-NetConnection 127.0.0.1 -Port 18080
Get-Process px -ErrorAction SilentlyContinue
```

Se necessario, rode:

```powershell
D:\IA-LAB\scripts\startup\startup_px.ps1
```

## VM `ia-lab` nao sobe

Validar:

```powershell
multipass list
Get-Service Multipass
```

Se a VM nao estiver `Running`, rode:

```powershell
D:\IA-LAB\scripts\startup\startup_vm.ps1
```

Se a VM tiver sido apagada, recrie com:

```powershell
D:\IA-LAB\scripts\setup\rebuild_multipass_vm.ps1 -DeleteExisting
```

## SSH do host `ia-lab` aponta para IP antigo

Rode:

```powershell
D:\IA-LAB\scripts\startup\update_ssh_config.ps1
```

Depois valide:

```powershell
Get-Content (Join-Path $env:USERPROFILE '.ssh\config')
```

## VSCode Remote SSH

Se SSH falhar:

- confirmar IP da VM com `multipass info ia-lab`
- confirmar `openssh-server` na VM
- testar `ssh ubuntu@<ip-da-vm>`
- revisar `~/.ssh/config`

## GitHub atras do proxy

Usar HTTPS com Git Credential Manager. Se a rede exigir proxy:

```powershell
git config --global http.proxy http://127.0.0.1:18080
git config --global https.proxy http://127.0.0.1:18080
```

Se falhar autenticacao, limpar credenciais antigas no Windows Credential Manager.
