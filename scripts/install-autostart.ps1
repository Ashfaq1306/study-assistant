<#
.SYNOPSIS
  Starts the public Study Assistant server (scripts\serve-public.ps1) every time you sign in to Windows,
  and starts it now. Run with -Remove to undo.

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File scripts\install-autostart.ps1
  powershell -ExecutionPolicy Bypass -File scripts\install-autostart.ps1 -Remove
#>
param([switch]$Remove)

$ErrorActionPreference = 'Stop'
$taskName = 'Study Assistant server'
$script = Join-Path $PSScriptRoot 'serve-public.ps1'

if (Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue) {
  Stop-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
  Unregister-ScheduledTask -TaskName $taskName -Confirm:$false
}
# The task's children (API and tunnel) outlive it; stop them so nothing is left half-running.
Get-CimInstance Win32_Process -Filter "Name='node.exe'" | Where-Object { $_.CommandLine -match 'dist[\\/]server\.js' } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force }
Get-Process cloudflared -ErrorAction SilentlyContinue | Stop-Process -Force

if ($Remove) { Write-Host "Removed '$taskName'."; return }

$action = New-ScheduledTaskAction -Execute 'powershell.exe' `
  -Argument "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$script`""
$trigger = New-ScheduledTaskTrigger -AtLogOn -User "$env:USERDOMAIN\$env:USERNAME"
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable `
  -ExecutionTimeLimit ([TimeSpan]::Zero) -RestartCount 999 -RestartInterval (New-TimeSpan -Minutes 1) -MultipleInstances IgnoreNew
Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Settings $settings `
  -Description 'Runs the Study Assistant API and its public tunnel (scripts\serve-public.ps1).' | Out-Null
Start-ScheduledTask -TaskName $taskName
Write-Host "Installed '$taskName': it runs at every sign-in and is starting now."
Write-Host "Logs: $env:LOCALAPPDATA\StudyAssistant\logs"
