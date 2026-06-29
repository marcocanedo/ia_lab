# Multipass Runtime

Este projeto pode rodar dentro da VM `ia-lab` no Multipass para reduzir atrito com antivirus no Windows.

## Fluxo base

No guest Ubuntu:

```bash
cd ~/ageste-difal
uv sync
uv run python malhas_agent/manage_app.py init-db
uv run python malhas_agent/manage_app.py create-user --username admin --role admin
./malhas_agent/start_app_linux.sh
```

## Proxy

Se a rede corporativa exigir proxy HTTP, configure no guest:

```bash
export HTTP_PROXY=http://172.20.0.1:18080
export HTTPS_PROXY=http://172.20.0.1:18080
export ALL_PROXY=http://172.20.0.1:18080
```

## Porta da aplicacao

A Streamlit sobe na VM em `0.0.0.0:8501`. Para acesso externo, o host Windows deve encaminhar a porta para o IP atual da VM.
