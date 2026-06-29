$ErrorActionPreference = 'Continue'

Stop-Service -Name RustDesk -Force -ErrorAction Continue
Get-Process -Name RustDesk -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction Continue
Start-Sleep -Seconds 3
Start-Service -Name RustDesk -ErrorAction Continue
Start-Sleep -Seconds 3
Start-Process -FilePath 'C:\Program Files\RustDesk\rustdesk.exe' -ErrorAction Continue
Start-Sleep -Seconds 5
sc.exe query RustDesk
Get-Process -Name RustDesk -ErrorAction SilentlyContinue | Select-Object ProcessName,Id,StartTime | Format-Table -AutoSize
