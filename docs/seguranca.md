# Seguranca

## Superficie exposta

Por padrao, o laboratorio deve expor servicos apenas localmente:

- Open WebUI via `127.0.0.1:3000`
- Ollama GPU via `127.0.0.1:11434`, CPU via `127.0.0.1:11435` e roteador via `127.0.0.1:11436`
- PX via `127.0.0.1:18080`

Ollama esta configurado como `0.0.0.0` nas portas `11434`, `11435` e `11436` para permitir acesso da VM. Isso deve ser protegido por firewall de host e rede confiavel. Para o Open WebUI, divulgar apenas o endpoint do roteador `11436`; backends diretos sao detalhe operacional.

## Segredos

Nao versionar:

- chaves SSH
- tokens GitHub
- arquivos `.env.local`
- certificados ou `.pem`
- dumps de volume com dados sensiveis

## Backups

Backups devem ser guardados em local protegido. O volume `open-webui` pode conter historico de chats e configuracoes.

## Recomendacoes

- Usar usuario administrativo apenas para tarefas que exigem portproxy e Task Scheduler.
- Manter `HTTP_PROXY` vazio dentro do container Open WebUI.
- Manter Open WebUI apontando para `http://10.14.0.226:11436`.
- Revisar regras de firewall antes de permitir acesso de outras maquinas.
