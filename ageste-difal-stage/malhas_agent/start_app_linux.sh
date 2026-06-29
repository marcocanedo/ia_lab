#!/usr/bin/env bash
set -euo pipefail

PORT="${1:-8501}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

cd "${PROJECT_ROOT}"
uv run streamlit run malhas_agent/app.py --server.address 0.0.0.0 --server.port "${PORT}" --server.headless true
