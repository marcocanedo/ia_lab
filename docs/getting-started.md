# Getting started

O IA-LAB e um laboratorio local de IA. O Windows hospeda PX, Ollama, o roteador Ollama, Task Scheduler e portproxy. A VM Multipass `ia-lab` hospeda Docker e o container Open WebUI.

Fluxo principal:

```text
Browser -> 127.0.0.1:3000 -> portproxy Windows -> VM ia-lab:3000 -> open-webui -> Ollama router 11436
```

## Primeiro acesso

1. Abra o Open WebUI em <http://127.0.0.1:3000>.
2. Se nao abrir, rode o healthcheck:

```powershell
D:\IA-LAB\scripts\maintenance\healthcheck.ps1
```

3. Se algum componente estiver indisponivel, rode o watchdog:

```powershell
D:\IA-LAB\scripts\maintenance\watchdog.ps1
```

## Leitura recomendada

- [Operacao diaria](operacao.md)
- [Arquitetura](arquitetura.md)
- [Troubleshooting](troubleshooting.md)
