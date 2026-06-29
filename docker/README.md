# Docker IA-LAB

Este diretorio contem a definicao Docker Compose do Open WebUI.

O compose foi criado para preservar o ambiente atual:

- porta publica continua `3000`
- container continua `open-webui`
- volume Docker continua `open-webui`
- endpoint Ollama continua `http://10.14.0.226:11436`
- variaveis de proxy HTTP ficam vazias dentro do container

## Validar

Dentro da VM `ia-lab`:

```bash
cd /mnt/c/IA-LAB/docker
docker compose config
```

Se o diretorio Windows nao estiver montado na VM, copie este diretorio para a VM ou execute os comandos equivalentes a partir de um caminho local da VM.

## Subir

Use apenas em janela de manutencao:

```bash
docker rm -f open-webui
docker compose up -d
```

## Backup rapido do volume

```bash
docker run --rm -v open-webui:/data -v "$PWD/backups:/backup" alpine \
  tar czf /backup/open-webui-data.tgz -C /data .
```
