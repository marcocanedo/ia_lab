# Seguranca

## Superficie exposta

Por padrao, o laboratorio deve expor servicos apenas localmente:

- PX via `127.0.0.1:18080`
- VM `ia-lab` via SSH no IP atual, porta `22`

## Segredos

Nao versionar:

- chaves SSH
- tokens GitHub
- arquivos `.env.local`
- certificados ou `.pem`
- dumps de volume com dados sensiveis

## Backups

Backups devem ser guardados em local protegido. A VM pode conter chaves e configuracoes de suporte.

## Recomendacoes

- Usar usuario administrativo apenas para tarefas que exigem Task Scheduler ou rebuild da VM.
- Manter o PX ativo antes de downloads em rede corporativa.
- Revisar regras de firewall antes de permitir acesso de outras maquinas.
