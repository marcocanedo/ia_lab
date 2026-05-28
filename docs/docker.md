# Docker

Docker roda dentro da VM Multipass `ia-lab`.

## Comandos

```powershell
multipass exec ia-lab -- docker ps
multipass exec ia-lab -- docker logs open-webui --tail 100
multipass exec ia-lab -- docker inspect open-webui
```

## Container principal

- nome: `open-webui`
- imagem: `ghcr.io/open-webui/open-webui:main`
- restart: `unless-stopped`
- porta VM: `3000`
- porta container: `8080`
- volume: `open-webui:/app/backend/data`

## Compose

Arquivo:

```text
C:\IA-LAB\docker\docker-compose.yml
```

O volume e externo para preservar dados existentes:

```yaml
volumes:
  open-webui:
    external: true
```

Migrar para compose apenas em janela de manutencao.

## Validacao realizada

O plugin Docker Compose foi instalado na VM pelo pacote Ubuntu:

```bash
sudo apt-get install -y docker-compose-v2
docker compose version
```

Versao validada:

```text
Docker Compose version 2.40.3+ds1-0ubuntu1
```

O comando `docker compose config` foi executado com sucesso usando os arquivos em `C:\IA-LAB\docker`.
