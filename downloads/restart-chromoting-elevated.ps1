$ErrorActionPreference = 'Continue'

Stop-Service -Name chromoting -Force -ErrorAction Continue
Start-Sleep -Seconds 5
Start-Service -Name chromoting -ErrorAction Continue
Start-Sleep -Seconds 10
sc.exe queryex chromoting
Get-Process -Name remoting_host -ErrorAction SilentlyContinue |
    Select-Object ProcessName,Id,StartTime,CPU,WorkingSet |
    Format-Table -AutoSize
