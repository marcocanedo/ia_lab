# GitHub

## Estado

Git for Windows esta instalado no host Windows.

Validar:

```powershell
git --version
git config --global --list
```

## Configuracao padrao

Script:

```powershell
C:\IA-LAB\scripts\setup\git_setup.ps1
```

Configura:

- Git Credential Manager
- branch inicial `main`
- `core.autocrlf=true`
- proxy HTTPS via PX

## Proxy

Configurar:

```powershell
git config --global http.proxy http://127.0.0.1:18080
git config --global https.proxy http://127.0.0.1:18080
```

Remover:

```powershell
git config --global --unset http.proxy
git config --global --unset https.proxy
```

## Repositorio IA-LAB

Arquivos versionaveis:

- `README.md`
- `docs/`
- `scripts/`
- `docker/`
- `.vscode/`
- `workspace/` sem dados sensiveis

Nao versionar:

- `backups/`
- logs
- credenciais
- dumps de volumes
