# Checklist de Restauracao da Nova Workstation

Data: 2026-05-31

## Antes de iniciar
- [ ] Confirmar acesso ao OneDrive com a pasta `BACKUP_WORKSTATION_2026`.
- [ ] Confirmar que o backup esta visivel e sem erros de sincronizacao.
- [ ] OneDrive sincronizado.
- [ ] BACKUP_WORKSTATION_2026 visivel na nova maquina.
- [ ] RESTORE_GUIDE.md aberto.
- [ ] Confirmar que o diretorio de destino da nova workstation esta vazio ou controlado.

## Ordem de restauracao
- [ ] Git instalado.
- [ ] VS Code instalado.
- [ ] Python/Conda instalado.
- [ ] WSL instalado.
- [ ] Docker instalado.
- [ ] Ollama instalado.
- [ ] IA-LAB restaurado.
- [ ] Extensoes VS Code restauradas.
- [ ] Configuracoes protegidas restauradas com cuidado.
- [ ] Ambientes Python restaurados.
- [ ] Modelos Ollama baixados/restaurados.
- [ ] Restaurar Open WebUI.

## Verificacoes finais
- [ ] Executar `09_SCRIPTS_RESTORE\\validar_ambiente_nova_workstation.ps1`.
- [ ] Validacao final executada.
- [ ] Validar `C:\\IA-LAB\\scripts\\healthcheck.ps1`.
- [ ] Confirmar funcionamento de `Ollama` em `127.0.0.1:11434`.
- [ ] Open WebUI validado.
- [ ] PX/Cntlm validado.
- [ ] Scripts de inicializacao revisados.
- [ ] Confirmar que segredos e permissoes foram revisados.

## Observacoes
- Pendencia registrada no backup original: `C:\\Users\\01481911775\\.ssh\\multipass_ia_lab`.
- Caso a nova workstation dependa desse arquivo, tratar como item separado de restauracao.

## Pendencias conhecidas
- `C:\\Users\\01481911775\\.ssh\\multipass_ia_lab` foi documentado como nao copiado no relatorio original do backup.
- Se a nova workstation depender dessa chave, a restauracao deve considerar esse item como risco residual.
- `C:\\Users\\01481911775\\.ssh\\multipass_ia_lab` nao foi copiado por acesso negado.
- Microsoft Silverlight permanece como pendencia residual.
- Recomenda-se recriar chave/instancia Multipass na nova workstation se necessario.
- Aguardar sincronizacao completa do OneDrive antes de desligar, formatar ou devolver a maquina antiga.

## Conclusao esperada
- [ ] Backup apto para restauracao com consistencia e sem conflitos de sincronizacao.

## Resultado final
- Backup do OneDrive validado como consistente e pronto para restauracao na nova workstation, com pendencias residuais documentadas.
