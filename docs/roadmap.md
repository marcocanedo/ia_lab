# Roadmap

## Curto prazo

- Eliminar instancia duplicada residual do PX em uma janela de manutencao.
- Validar o boot da VM `ia-lab` e o sincronismo SSH apos reinicios do Windows.
- Criar snapshot inicial manual da VM apos confirmar espaco em disco.
- Consolidar o playbook de acesso remoto e proxy APT da VM.

## Medio prazo

- Padronizar o repositorio Git do IA-LAB.
- Adicionar testes Pester para scripts PowerShell.
- Criar playbook de restore completo da VM base.
- Adicionar hardening simples para PX, SSH e Task Scheduler.

## Longo prazo

- Adicionar observabilidade com metricas simples e historico de disponibilidade.
- Criar imagens ou templates reproduziveis da VM base.
- Adicionar automacoes auxiliares para manutencao de Windows e Multipass.
