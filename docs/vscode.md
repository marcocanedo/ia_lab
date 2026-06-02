# VSCode

## Workspace

Arquivo:

```text
C:\IA-LAB\IA-LAB.code-workspace
```

## Extensoes recomendadas

Definidas em:

```text
C:\IA-LAB\.vscode\extensions.json
```

Incluem:

- Remote SSH
- Python
- Pylance
- Jupyter
- Docker
- GitHub Actions
- Mermaid

## Remote SSH

Host SSH configurado:

```sshconfig
Host ia-lab
    HostName <ip-da-vm-atual>
    User ubuntu
    IdentityFile C:\Users\01481911775\.ssh\ia_lab_ed25519
    IdentitiesOnly yes
```

O script abaixo atualiza automaticamente o IP do host `ia-lab` quando a VM muda de endereco:

```powershell
C:\IA-LAB\scripts\startup\update_ssh_config.ps1
```

O `startup_vm.ps1` tambem chama esse script durante a inicializacao.

## Python remoto

Na VM:

```bash
python3 -m venv ~/venvs/ia-lab
source ~/venvs/ia-lab/bin/activate
python -m pip install --upgrade pip
```

Use o kernel remoto no VSCode para notebooks.
