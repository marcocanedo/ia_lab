. "$PSScriptRoot\_llamacpp_common.ps1"
Start-LlamaModel -Name "qwen25_7b" -ModelDirectory "qwen2.5-7b-instruct-q5_k_m" -ModelPattern "qwen2.5-7b-instruct-q5_k_m*.gguf" -Port 8001 -Context 8192 -GpuLayers 999 -ModelAlias "qwen2.5-7b-instruct-gguf-q5_k_m"
