<#
.SYNOPSIS
  Turns on AI exams and the AI study helper: asks for your Gemini API key (typing is hidden),
  checks it with Google, saves it in backend\.env and restarts the API.

  Get a key at https://aistudio.google.com/apikey ("Copy key" on your "Study Mate" key).

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File scripts\set-ai-key.ps1
#>
$ErrorActionPreference = 'Stop'
$envFile = Join-Path (Split-Path -Parent $PSScriptRoot) 'backend\.env'

$secure = Read-Host -Prompt 'Paste your Gemini API key (hidden), then press Enter' -AsSecureString
$ptr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
try { $key = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($ptr).Trim() } finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr) }
if (-not $key) { Write-Host 'No key entered; nothing changed.' -ForegroundColor Yellow; exit 1 }

Write-Host 'Checking the key with Google...'
try {
  $models = Invoke-RestMethod -Uri 'https://generativelanguage.googleapis.com/v1beta/models?pageSize=200' -Headers @{ 'x-goog-api-key' = $key } -TimeoutSec 20
  $names = $models.models.name -replace '^models/', ''
} catch {
  Write-Host "Google did not accept this key: $($_.Exception.Message)" -ForegroundColor Red
  Write-Host 'Nothing changed. Copy the key again from https://aistudio.google.com/apikey and retry.'
  exit 1
}

# Use the configured model if this key can reach it, else the best Flash model it can.
$lines = [System.Collections.Generic.List[string]](Get-Content $envFile -Encoding utf8)
function Set-EnvValue([string]$name, [string]$value) {
  for ($i = 0; $i -lt $lines.Count; $i++) { if ($lines[$i] -match "^$name=") { $lines[$i] = "$name=$value"; return } }
  $lines.Add("$name=$value")
}
$wanted = ($lines | Where-Object { $_ -match '^GEMINI_MODEL=' }) -replace '^GEMINI_MODEL=', ''
if ($names -notcontains $wanted) {
  $flash = $names | Where-Object { $_ -match '^gemini-[\d.]+-flash$' } | Sort-Object { [version](($_ -replace '^gemini-([\d.]+)-flash$', '$1') + '.0') } -Descending | Select-Object -First 1
  if ($flash) { Write-Host "Model $wanted is not available to this key; using $flash."; Set-EnvValue 'GEMINI_MODEL' $flash }
}
Set-EnvValue 'GEMINI_API_KEY' $key
Set-EnvValue 'AI_PROVIDER' 'gemini'
[IO.File]::WriteAllLines($envFile, $lines, (New-Object System.Text.UTF8Encoding $false))
$key = $null

# Restart the API; scripts\serve-public.ps1 starts it again within 30 seconds.
Get-CimInstance Win32_Process -Filter "Name='node.exe'" |
  Where-Object { $_.CommandLine -match 'dist[\\/]server\.js' } |
  ForEach-Object { Stop-Process -Id $_.ProcessId -Force }
Write-Host 'Saved. AI exams and the study helper are on; the server restarts within 30 seconds.' -ForegroundColor Green
