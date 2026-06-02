# Scripts legados

Esta pasta guarda artefatos que nao fazem parte da rotina operacional atual do IA-LAB, mas foram preservados para auditoria, consulta ou repeticao controlada de uma fase especifica.

## workstation_cleanup

- `fase3_limpeza_controlada.ps1`
- `fase3_limpeza_controlada_verbose.ps1`

Scripts usados na fase de limpeza controlada da workstation. O `verbose` substituiu o primeiro durante a execucao pratica por ter `DryRun`, checkpoints e melhor observabilidade. Ambos devem ser tratados como ferramentas de fase, nao como automacao diaria do IA-LAB.

## task_backups

Backups historicos de tarefas antigas do Windows Task Scheduler e configuracoes relacionadas. A automacao atual deve ser recriada pelos scripts:

- `scripts\configure_startup_tasks.ps1`
- `scripts\configure_maintenance_tasks.ps1`

## piloto_openwebui

Documentacao do piloto de exposicao corporativa do Open WebUI. O acesso corporativo atual deve ser revisado em janela controlada antes de reativar qualquer portproxy ou regra de firewall.
