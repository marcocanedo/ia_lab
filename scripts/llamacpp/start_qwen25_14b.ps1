param(
    [int]$Context = 4096
)

. "$PSScriptRoot\_llamacpp_common.ps1"
Start-LlamaModel -Name "qwen25_14b" -ModelDirectory "qwen2.5-14b-instruct-q4_k_m" -ModelPattern "qwen2.5-14b-instruct-q4_k_m*.gguf" -Port 8003 -Context $Context -GpuLayers 999 -ModelAlias "qwen2.5-14b-instruct-gguf-q4_k_m"
