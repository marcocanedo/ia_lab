# Roadmap

## Curto prazo

- Eliminar instancia duplicada residual do PX em uma janela de manutencao.
- Revisar portproxy corporativo antigo `10.14.0.226:3000 -> 172.21.150.39:3000`; o portproxy local validado e `127.0.0.1:3000 -> 172.25.122.220:3000`.
- Validar `docker compose config` dentro da VM.
- Criar snapshot inicial manual da VM apos confirmar espaco em disco.
- Configurar SSH estavel para VSCode Remote.

## Medio prazo

- Padronizar repositorio Git do IA-LAB.
- Adicionar testes Pester para scripts PowerShell.
- Criar playbook de restore completo.
- Mover operacao do Open WebUI para Docker Compose em janela controlada.

## Longo prazo

- Adicionar stack RAG local.
- Adicionar pipelines de avaliacao de prompts.
- Adicionar notebooks remotos com kernel Python na VM.
- Criar observabilidade com metricas simples e historico de disponibilidade.
