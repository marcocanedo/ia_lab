. "$PSScriptRoot\_llamacpp_common.ps1"
Start-LlamaModel -Name "qwen25_coder_7b" -ModelDirectory "qwen2.5-coder-7b-instruct-q5_k_m" -ModelPattern "qwen2.5-coder-7b-instruct-q5_k_m-*.gguf" -Port 8002 -Context 8192 -GpuLayers 999 -ModelAlias "qwen2.5-coder-7b-instruct-gguf-q5_k_m"
