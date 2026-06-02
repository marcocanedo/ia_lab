# Checklist de Restauracao OneDrive

Data: 2026-05-31

## Antes de iniciar
- [ ] Confirmar acesso ao OneDrive com a pasta `BACKUP_WORKSTATION_2026`.
- [ ] Confirmar que o backup esta visivel e sem erros de sincronizacao.
- [ ] Confirmar que o diretorio de destino da nova workstation esta vazio ou controlado.

## Ordem de restauracao
- [ ] Instalar Git.
- [ ] Instalar VS Code.
- [ ] Instalar Python e Conda.
- [ ] Habilitar WSL se necessario.
- [ ] Instalar Docker.
- [ ] Instalar Ollama.
- [ ] Restaurar IA-LAB com `09_SCRIPTS_RESTORE\\restore_ia_lab.ps1`.
- [ ] Restaurar configuracoes protegidas com cuidado.
- [ ] Restaurar extensoes do VS Code.
- [ ] Revisar ambientes Python.
- [ ] Revisar modelos Ollama.
- [ ] Restaurar Open WebUI.

## Verificacoes finais
- [ ] Executar `09_SCRIPTS_RESTORE\\validar_ambiente_nova_workstation.ps1`.
- [ ] Validar `C:\\IA-LAB\\scripts\\healthcheck.ps1`.
- [ ] Confirmar funcionamento de `Ollama` em `127.0.0.1:11434`.
- [ ] Confirmar funcionamento de `Open WebUI` em `127.0.0.1:3000`.
- [ ] Confirmar que segredos e permissoes foram revisados.

## Observacoes
- Pendencia registrada no backup original: `C:\\Users\\01481911775\\.ssh\\multipass_ia_lab`.
- Caso a nova workstation dependa desse arquivo, tratar como item separado de restauracao.

## Conclusao esperada
- [ ] Backup apto para restauracao com consistencia e sem conflitos de sincronizacao.
