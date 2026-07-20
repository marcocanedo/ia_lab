#!/usr/bin/env bash
set -euo pipefail

proxy_port="${1:-18080}"
gateway="$(ip route show default | awk 'NR == 1 { print $3 }')"

if [[ -z "${gateway}" ]]; then
    echo "Nao foi possivel detectar o gateway do host Windows." >&2
    exit 1
fi

proxy_url="http://${gateway}:${proxy_port}"
server_dir="${HOME}/.vscode-server"
env_file="${server_dir}/server-env-setup"
machine_dir="${server_dir}/data/Machine"
settings_file="${machine_dir}/settings.json"

mkdir -p "${server_dir}" "${machine_dir}"
cat > "${env_file}" <<EOF
export HTTP_PROXY="${proxy_url}"
export HTTPS_PROXY="${proxy_url}"
export ALL_PROXY="${proxy_url}"
export NO_PROXY="localhost,127.0.0.1,::1,${gateway}"
export http_proxy="${proxy_url}"
export https_proxy="${proxy_url}"
export all_proxy="${proxy_url}"
export no_proxy="localhost,127.0.0.1,::1,${gateway}"
EOF
chmod 600 "${env_file}"

python3 - "${settings_file}" "${proxy_url}" <<'PY'
import json
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
proxy_url = sys.argv[2]

try:
    settings = json.loads(path.read_text(encoding="utf-8")) if path.exists() else {}
except json.JSONDecodeError as exc:
    raise SystemExit(f"JSON invalido em {path}: {exc}")

settings.update({
    "http.proxy": proxy_url,
    "http.proxySupport": "override",
    "http.proxyStrictSSL": False,
})
path.write_text(json.dumps(settings, indent=4) + "\n", encoding="utf-8")
PY

echo "VS Code Server configurado para usar ${proxy_url}"
echo "Reconecte a janela Remote SSH para aplicar o ambiente."
