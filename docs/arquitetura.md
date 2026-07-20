# Arquitetura

## Visao geral

O IA-LAB usa o Windows como host principal, PX como proxy NTLM local e Multipass para manter uma VM Ubuntu isolada.

```text
Browser / ferramentas -> PX 127.0.0.1:18080 -> Internet
Windows -> Multipass service -> VM Ubuntu ia-lab -> SSH / VS Code Remote
```

## Dependencias

1. PX precisa estar ativo para downloads e acessos em rede restrita.
2. Multipass precisa conseguir iniciar a VM `ia-lab`.
3. A VM precisa manter SSH habilitado para acesso remoto.
4. O arquivo `~\.ssh\config` do usuario deve apontar para o IP atual da VM.

## Decisoes tecnicas

- PX fica no host Windows porque e a camada mais simples para proxy corporativo.
- Multipass fica responsavel apenas pela VM base.
- A VM `ia-lab` e usada como ponto de apoio para SSH, VS Code Remote e comandos administrativos.
- A configuracao SSH do usuario e sincronizada por `update_ssh_config.ps1`.

## Persistencia

- Scripts: `D:\IA-LAB\scripts`
- Logs: `D:\IA-LAB\scripts\logs`
- Backups e snapshots: mantenha em local protegido fora do caminho ativo
- VM: `ia-lab`
