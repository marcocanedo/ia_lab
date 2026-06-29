param(
    [int]$Port = 8501
)

$ErrorActionPreference = "Stop"
$ProjectRoot = Split-Path -Parent $PSScriptRoot

Set-Location $ProjectRoot
uv run streamlit run malhas_agent/app.py --server.address 0.0.0.0 --server.port $Port --server.headless true
