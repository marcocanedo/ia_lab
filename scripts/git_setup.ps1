param(
    [switch]$DisableProxy
)

$ErrorActionPreference = "Stop"

$git = Get-Command git -ErrorAction Stop
Write-Output "Git encontrado: $($git.Source)"
git --version

git config --global credential.helper manager
git config --global init.defaultBranch main
git config --global core.autocrlf true
git config --global pull.rebase false

if ($DisableProxy) {
    git config --global --unset http.proxy 2>$null
    git config --global --unset https.proxy 2>$null
    Write-Output "Proxy Git removido."
}
else {
    git config --global http.proxy http://127.0.0.1:18080
    git config --global https.proxy http://127.0.0.1:18080
    Write-Output "Proxy Git configurado para PX em http://127.0.0.1:18080"
}

Write-Output "Configuracao Git atual:"
git config --global --list
