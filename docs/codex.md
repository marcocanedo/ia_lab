# Codex

## Papel no IA-LAB

Codex deve atuar como agente de automacao e desenvolvimento, usando scripts versionados e operacoes reproduziveis.

## Regras operacionais

- Validar estado antes de alterar.
- Criar backup antes de mudancas estruturais.
- Preferir scripts idempotentes.
- Nao apagar volumes Docker sem backup.
- Nao alterar portas sem decisao explicita.

## Comandos uteis

```powershell
C:\IA-LAB\scripts\maintenance\healthcheck.ps1
C:\IA-LAB\scripts\maintenance\backup_configs.ps1
```

## Areas futuras

- agentes em `workspace\agents`
- RAG em `workspace\rag`
- prompts em `workspace\prompts`
- pipelines em `workspace\pipelines`
