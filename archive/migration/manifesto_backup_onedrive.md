# Manifesto do Backup OneDrive

Data: 2026-05-31

## Identificacao
- Nome do backup: `BACKUP_WORKSTATION_2026`
- Local: `C:\Users\01481911775\OneDrive - Secretaria da Fazenda do Parana\BACKUP_WORKSTATION_2026`

## Estado geral
- Backup presente: sim
- Estrutura principal presente: sim
- Arquivos essenciais presentes: sim
- Scripts de restauracao presentes: sim
- Guia de restauracao presente: sim
- Pendencias de sincronizacao: nao detectadas
- Erros de sincronizacao: nao detectados
- Conflitos de sincronizacao: nao detectados

## Pastas validadas
- `00_RELATORIOS_INVENTARIO`
- `01_IA_LAB`
- `02_CONFIGS`
- `03_EXPORTS`
- `04_SSH_PROTEGIDO`
- `05_OLLAMA`
- `06_CODEX`
- `07_VSCODE`
- `08_DOCUMENTOS_TECNICOS`
- `09_SCRIPTS_RESTORE`
- `10_RESTORE_GUIDE`

## Arquivos essenciais validados
- `backup_fase6_operacao.log`
- `validacao_backup_onedrive.md`
- `03_EXPORTS\conda_envs.txt`
- `03_EXPORTS\pip_freeze_global.txt`
- `03_EXPORTS\vscode_extensions.txt`
- `03_EXPORTS\ollama_models.txt`
- `03_EXPORTS\docker_images.txt`
- `03_EXPORTS\winget_list_final.txt`
- `04_SSH_PROTEGIDO\sensibilidade_backup.md`
- `09_SCRIPTS_RESTORE\restore_ia_lab.ps1`
- `09_SCRIPTS_RESTORE\validar_ambiente_nova_workstation.ps1`
- `10_RESTORE_GUIDE\RESTORE_GUIDE.md`

## Observacoes
- A pendencia documentada de `C:\Users\01481911775\.ssh\multipass_ia_lab` permaneceu registrada no relatorio original do backup.
- A validacao final do OneDrive nao indicou arquivos pendentes, erros ou conflitos.

## Conclusao
O backup foi considerado consistente e pronto para restauracao na nova workstation.
