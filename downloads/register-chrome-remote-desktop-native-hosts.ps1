$ErrorActionPreference = 'Stop'

$base = 'C:\Program Files (x86)\Google\Chrome Remote Desktop\149.0.7827.18'
$entries = @(
    @('HKLM:\SOFTWARE\Google\Chrome\NativeMessagingHosts\com.google.chrome.remote_desktop', "$base\com.google.chrome.remote_desktop.json"),
    @('HKLM:\SOFTWARE\Google\Chrome\NativeMessagingHosts\com.google.chrome.remote_assistance', "$base\com.google.chrome.remote_assistance.json"),
    @('HKLM:\SOFTWARE\Google\Chrome\NativeMessagingHosts\com.google.chrome.remote_webauthn', "$base\com.google.chrome.remote_webauthn.json"),
    @('HKLM:\SOFTWARE\Microsoft\Edge\NativeMessagingHosts\com.google.chrome.remote_desktop', "$base\com.google.chrome.remote_desktop.json"),
    @('HKLM:\SOFTWARE\Microsoft\Edge\NativeMessagingHosts\com.google.chrome.remote_assistance', "$base\com.google.chrome.remote_assistance.json"),
    @('HKLM:\SOFTWARE\Microsoft\Edge\NativeMessagingHosts\com.google.chrome.remote_webauthn', "$base\com.google.chrome.remote_webauthn.json")
)

foreach ($entry in $entries) {
    New-Item -Path $entry[0] -Force | Out-Null
    Set-ItemProperty -Path $entry[0] -Name '(default)' -Value $entry[1]
}

Restart-Service -Name chromoting -Force -ErrorAction Continue
Start-Sleep -Seconds 5
sc.exe queryex chromoting
