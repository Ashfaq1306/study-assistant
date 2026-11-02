<#
.SYNOPSIS
  Moves the server from this computer to Render: copies all data into Render's Postgres, points the
  apps at the Render address, and stops the server on this computer.

.DESCRIPTION
  Run once, after the Render service is live (https://<name>.onrender.com/health answers).
  1. Asks for Render's *External Database URL* (Render → study-assistant-db → Connect → External; hidden).
  2. Stops the server on this computer, so nothing changes during the copy.
  3. Copies every row from backend\prisma\dev.db into the (empty) Render database.
  4. Writes the Render address into the address gist, so installed apps switch over by themselves.
  5. Removes the "Study Assistant server" autostart task (this computer is no longer the server).
  The local dev.db is kept as a backup. Nothing secret is printed or saved.

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File scripts\move-to-render.ps1 -RenderUrl https://study-assistant-api.onrender.com
#>
param(
  [Parameter(Mandatory)] [string]$RenderUrl,
  [string]$GistId = '73f5cd0421af834e9965f8680d2ea2b1',
  [string]$GistFile = 'study-assistant-endpoint.json'
)
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$backend = Join-Path $repo 'backend'
$RenderUrl = $RenderUrl.TrimEnd('/')
if ($RenderUrl -notmatch '^https://') { throw 'RenderUrl must start with https://' }

Write-Host "Checking $RenderUrl ..."
try { $null = Invoke-WebRequest "$RenderUrl/health" -UseBasicParsing -TimeoutSec 30 } catch { throw "The Render service is not answering at $RenderUrl/health yet. Wait for the deploy to finish." }

$secure = Read-Host -Prompt "Paste Render's External Database URL (hidden), then press Enter" -AsSecureString
$ptr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
try { $dbUrl = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($ptr).Trim() } finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr) }
if ($dbUrl -notmatch '^postgres(ql)?://') { throw 'That does not look like a Postgres URL (it starts with postgresql://).' }
if ($dbUrl -notmatch 'sslmode=') { $dbUrl += $(if ($dbUrl.Contains('?')) { '&' } else { '?' }) + 'sslmode=require' }

Write-Host 'Stopping the server on this computer...'
Stop-ScheduledTask -TaskName 'Study Assistant server' -ErrorAction SilentlyContinue
Get-CimInstance Win32_Process -Filter "Name='node.exe'" | Where-Object { $_.CommandLine -match 'dist[\\/]server\.js' } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force }
Get-Process cloudflared -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep 2

$export = Join-Path $env:TEMP "study-assistant-export-$(Get-Random).json"
Push-Location $backend
try {
  Write-Host 'Reading the data on this computer...'
  $env:DATABASE_URL = 'file:./dev.db'
  node scripts/copy-data.mjs export $export
  if ($LASTEXITCODE -ne 0) { throw 'Export failed.' }

  Write-Host 'Copying it into Render...'
  node scripts/prisma-provider.mjs postgresql | Out-Null
  npx prisma generate | Out-Null
  $env:DATABASE_URL = $dbUrl
  npx prisma db push --skip-generate | Out-Null
  if ($LASTEXITCODE -ne 0) { throw 'Could not prepare the Render database.' }
  node scripts/copy-data.mjs import $export
  if ($LASTEXITCODE -ne 0) { throw 'Import failed (the Render database must be empty).' }
} finally {
  Remove-Item $export -ErrorAction SilentlyContinue
  Remove-Item Env:DATABASE_URL -ErrorAction SilentlyContinue
  $dbUrl = $null
  node scripts/prisma-provider.mjs sqlite | Out-Null
  npx prisma generate | Out-Null
  Pop-Location
}

Write-Host 'Pointing the apps at Render...'
$payload = @{ files = @{ $GistFile = @{ content = (@{ apiBaseUrl = $RenderUrl; updatedAt = (Get-Date).ToUniversalTime().ToString('o') } | ConvertTo-Json -Compress) } } } | ConvertTo-Json -Depth 5 -Compress
$tmp = New-TemporaryFile
[IO.File]::WriteAllText($tmp, $payload)
gh api --method PATCH "gists/$GistId" --input $tmp.FullName | Out-Null
Remove-Item $tmp

Write-Host 'Removing the server autostart on this computer...'
& (Join-Path $PSScriptRoot 'install-autostart.ps1') -Remove

Write-Host ''
Write-Host "Done. The app now runs on $RenderUrl" -ForegroundColor Green
Write-Host 'Phones switch over the next time they open the app. Your old data stays in backend\prisma\dev.db as a backup.'
