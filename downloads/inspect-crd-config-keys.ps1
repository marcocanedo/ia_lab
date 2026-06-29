$ErrorActionPreference = 'Stop'

foreach ($path in @(
    'C:\ProgramData\Google\Chrome Remote Desktop\host.json',
    'C:\ProgramData\Google\Chrome Remote Desktop\host_unprivileged.json'
)) {
    Write-Output "FILE: $path"
    if (Test-Path $path) {
        $json = Get-Content $path -Raw | ConvertFrom-Json
        $json.PSObject.Properties.Name | Sort-Object
    } else {
        Write-Output 'MISSING'
    }
}
