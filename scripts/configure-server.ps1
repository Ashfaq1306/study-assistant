<#
.SYNOPSIS
  Turns on real one-time codes by email (Gmail), and optionally the AI key, for the server on this computer.

.DESCRIPTION
  Asks for each secret in this window (typed text is hidden), writes it to backend\.env, sends a test
  email, then switches the server to production mode: codes are emailed for real and are never shown in
  the app or printed in the log. Secrets never leave this computer.

  Gmail needs an *app password* (not your normal password):
    1. Turn on 2-Step Verification:   https://myaccount.google.com/signinoptions/twosv
    2. Create an app password:        https://myaccount.google.com/apppasswords   (name it "Study Assistant")
    3. Copy the 16-letter password it shows, and paste it here when asked.

  Run again any time to change a value. Press Enter to keep the current one.

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File scripts\configure-server.ps1
#>
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$backend = Join-Path $repo 'backend'
$envFile = Join-Path $backend '.env'
if (-not (Test-Path $envFile)) { Copy-Item (Join-Path $backend '.env.example') $envFile }

$lines = [System.Collections.Generic.List[string]](Get-Content $envFile -Encoding utf8)

function Get-EnvValue([string]$key) {
  foreach ($line in $lines) { if ($line -match "^$key=(.*)$") { return $Matches[1].Trim('"') } }
  return ''
}

function Set-EnvValue([string]$key, [string]$value) {
  $quoted = if ($value -match '[\s#"<>]') { '"' + $value.Replace('"', '') + '"' } else { $value }
  for ($i = 0; $i -lt $lines.Count; $i++) {
    if ($lines[$i] -match "^$key=") { $lines[$i] = "$key=$quoted"; return }
  }
  $lines.Add("$key=$quoted")
}

function Read-Secret([string]$prompt) {
  $secure = Read-Host -Prompt $prompt -AsSecureString
  $ptr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
  try { return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($ptr) } finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr) }
}

Write-Host ''
Write-Host 'Study Assistant server setup' -ForegroundColor Magenta
Write-Host 'Press Enter to keep a current value.'
Write-Host ''

# --- Email (Gmail) ---
$currentUser = Get-EnvValue 'SMTP_USER'
$gmail = Read-Host -Prompt "Gmail address that sends the codes$(if ($currentUser) { " [$currentUser]" })"
if (-not $gmail) { $gmail = $currentUser }
if (-not $gmail -or $gmail -notmatch '@') { throw 'A Gmail address is needed to send codes.' }

$appPassword = (Read-Secret 'Gmail app password (16 letters, spaces are fine; hidden)') -replace '\s', ''
if (-not $appPassword) { $appPassword = Get-EnvValue 'SMTP_PASS' }
if (-not $appPassword) { throw 'The app password is needed. Create one at https://myaccount.google.com/apppasswords' }

Set-EnvValue 'EMAIL_PROVIDER' 'smtp'
Set-EnvValue 'SMTP_HOST' 'smtp.gmail.com'
Set-EnvValue 'SMTP_PORT' '587'
Set-EnvValue 'SMTP_USER' $gmail
Set-EnvValue 'SMTP_PASS' $appPassword
Set-EnvValue 'SMTP_FROM' "Study Assistant <$gmail>"

# --- AI (optional) ---
$hasAi = [bool](Get-EnvValue 'GEMINI_API_KEY')
$gemini = Read-Secret "Gemini API key from https://aistudio.google.com/apikey (optional$(if ($hasAi) { ', one is set' }); hidden)"
if ($gemini) { Set-EnvValue 'GEMINI_API_KEY' $gemini.Trim() }

# --- SMS ---
# Without an SMS provider the app offers codes by email only.
if ((Get-EnvValue 'SMS_PROVIDER') -ne 'twilio') { Set-EnvValue 'SMS_PROVIDER' 'none' }

[IO.File]::WriteAllLines($envFile, $lines, (New-Object System.Text.UTF8Encoding $false))
Write-Host 'Saved backend\.env' -ForegroundColor Green

# --- Test the email before switching ---
Write-Host "Sending a test email to $gmail ..."
Push-Location $backend
try { & npm run --silent email:check -- $gmail } finally { Pop-Location }
if ($LASTEXITCODE -ne 0) {
  Write-Host 'The test email failed, so the server was left as it was. Check the app password and run this again.' -ForegroundColor Red
  exit 1
}

# --- Production mode: real codes only ---
Set-EnvValue 'NODE_ENV' 'production'
Set-EnvValue 'EXPOSE_DEV_CODES' 'false'
[IO.File]::WriteAllLines($envFile, $lines, (New-Object System.Text.UTF8Encoding $false))

# Restart the API; scripts\serve-public.ps1 starts it again within 30 seconds.
Get-CimInstance Win32_Process -Filter "Name='node.exe'" |
  Where-Object { $_.CommandLine -match 'dist[\\/]server\.js' } |
  ForEach-Object { Stop-Process -Id $_.ProcessId -Force }

Write-Host ''
Write-Host 'Done. Codes are now emailed for real. Check your inbox for the test email.' -ForegroundColor Green
Write-Host 'The server restarts by itself within 30 seconds.'
