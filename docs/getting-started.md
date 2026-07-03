# Getting started

O IA-LAB agora e um laboratorio de infraestrutura base. O Windows hospeda PX e Multipass; a VM Ubuntu `ia-lab` fica disponivel para SSH e suporte.

Fluxo principal:

```text
Browser ou terminal -> PX -> Internet
Windows -> Multipass -> VM ia-lab -> SSH / VS Code Remote
```

## Primeiro acesso

1. Confirme que o PX responde em <http://127.0.0.1:18080>.
2. Liste a VM:

```powershell
multipass list
```

3. Se o ambiente nao estiver pronto, rode o healthcheck:

```powershell
D:\IA-LAB\scripts\maintenance\healthcheck.ps1
```

4. Se PX ou a VM base estiverem indisponiveis, rode o watchdog:

```powershell
D:\IA-LAB\scripts\maintenance\watchdog.ps1
```

## Leitura recomendada

- [Operacao diaria](operacao.md)
- [Arquitetura](arquitetura.md)
- [Troubleshooting](troubleshooting.md)
