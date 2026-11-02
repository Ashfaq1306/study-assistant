<#
.SYNOPSIS
  Runs the Study Assistant API on this computer and makes it reachable from any network.

.DESCRIPTION
  1. Starts the API (backend/dist/server.js) on 127.0.0.1 only, so nothing on the LAN can reach it directly.
  2. Opens a Cloudflare quick tunnel (free, no account): an HTTPS address like https://xyz.trycloudflare.com.
  3. Publishes that address to a GitHub gist. The app reads the gist when it starts and whenever the
     server stops answering, so a new tunnel address reaches every phone within a minute or two.
  4. Watches both every 30 s and restarts whichever one died (and republishes the address).

  Needs: Node 24, cloudflared (winget install Cloudflare.cloudflared), and the GitHub CLI signed in
  with the "gist" scope. The computer must be on and awake for the app to work.

  Logs: %LOCALAPPDATA%\StudyAssistant\logs

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File scripts\serve-public.ps1
#>
param(
  [string]$GistId = $(if ($env:STUDY_ASSISTANT_GIST) { $env:STUDY_ASSISTANT_GIST } else { '73f5cd0421af834e9965f8680d2ea2b1' }),
  [string]$GistFile = 'study-assistant-endpoint.json',
  [int]$Port = 8080,
  [int]$CheckEverySeconds = 30
)

$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$backend = Join-Path $repo 'backend'
$logDir = Join-Path $env:LOCALAPPDATA 'StudyAssistant\logs'
New-Item -ItemType Directory -Force $logDir | Out-Null
$mainLog = Join-Path $logDir 'serve-public.log'

function Log([string]$message) {
  $line = '{0:u}  {1}' -f (Get-Date).ToUniversalTime(), $message
  Add-Content -Path $mainLog -Value $line -Encoding utf8
  Write-Host $line
}

function Save-OldLog([string]$name) {
  # Start-Process can only overwrite, so keep the previous run's log (the last 10 per kind).
  $path = Join-Path $logDir $name
  if (-not (Test-Path $path) -or (Get-Item $path).Length -eq 0) { return }
  $stamp = (Get-Item $path).LastWriteTime.ToString('yyyyMMdd-HHmmss')
  Move-Item $path (Join-Path $logDir ("{0}.{1}{2}" -f [IO.Path]::GetFileNameWithoutExtension($name), $stamp, [IO.Path]::GetExtension($name))) -Force
  $pattern = '{0}.*{1}' -f [IO.Path]::GetFileNameWithoutExtension($name), [IO.Path]::GetExtension($name)
  Get-ChildItem $logDir -Filter $pattern | Where-Object { $_.Name -ne $name } |
    Sort-Object LastWriteTime -Descending | Select-Object -Skip 10 | Remove-Item -Force
  # The privacy policy promises server logs (IP addresses, times) are gone within 30 days.
  Get-ChildItem $logDir -Filter $pattern | Where-Object { $_.Name -ne $name -and $_.LastWriteTime -lt (Get-Date).AddDays(-30) } |
    Remove-Item -Force
}

function Find-Exe([string]$name, [string[]]$fallbacks) {
  $cmd = Get-Command $name -ErrorAction SilentlyContinue
  if ($cmd) { return $cmd.Source }
  foreach ($path in $fallbacks) { if (Test-Path $path) { return $path } }
  throw "$name not found. Install it first."
}

$node = Find-Exe 'node' @("$env:ProgramFiles\nodejs\node.exe")
$cloudflared = Find-Exe 'cloudflared' @("${env:ProgramFiles(x86)}\cloudflared\cloudflared.exe", "$env:ProgramFiles\cloudflared\cloudflared.exe")
$gh = Find-Exe 'gh' @("$env:ProgramFiles\GitHub CLI\gh.exe")

function Test-Url([string]$url) {
  try {
    $res = Invoke-WebRequest -Uri "$url/health" -UseBasicParsing -TimeoutSec 10
    return $res.StatusCode -eq 200
  } catch { return $false }
}

$script:api = $null
$script:tunnel = $null
$script:publicUrl = $null
$script:publishedUrl = $null

function Start-Api {
  if (Test-Url "http://127.0.0.1:$Port") { Log "API already answering on :$Port"; return }
  if (-not (Test-Path (Join-Path $backend 'dist\server.js'))) {
    Log 'Building the API (first run)'
    Push-Location $backend
    try { & npm run build | Out-Null } finally { Pop-Location }
  }
  Save-OldLog 'api.log'
  Save-OldLog 'api.err.log'
  Log 'Starting the API'
  $script:api = Start-Process -FilePath $node -WorkingDirectory $backend -WindowStyle Hidden -PassThru `
    -ArgumentList '--env-file-if-exists=.env', 'dist/server.js' `
    -RedirectStandardOutput (Join-Path $logDir 'api.log') -RedirectStandardError (Join-Path $logDir 'api.err.log')
  for ($i = 0; $i -lt 30; $i++) {
    Start-Sleep -Seconds 1
    if (Test-Url "http://127.0.0.1:$Port") { Log 'API is up'; return }
  }
  Log 'API did not answer within 30 s (see api.err.log)'
}

function Start-Tunnel {
  if ($script:tunnel -and -not $script:tunnel.HasExited) { Stop-Process -Id $script:tunnel.Id -Force -ErrorAction SilentlyContinue }
  Save-OldLog 'tunnel.log'
  $tunnelLog = Join-Path $logDir 'tunnel.log'
  Log 'Opening a Cloudflare quick tunnel'
  $script:tunnel = Start-Process -FilePath $cloudflared -WindowStyle Hidden -PassThru `
    -ArgumentList 'tunnel', '--no-autoupdate', '--url', "http://127.0.0.1:$Port" `
    -RedirectStandardOutput (Join-Path $logDir 'tunnel.out.log') -RedirectStandardError $tunnelLog
  $script:publicUrl = $null
  for ($i = 0; $i -lt 60 -and -not $script:publicUrl; $i++) {
    Start-Sleep -Seconds 1
    if (Test-Path $tunnelLog) {
      $match = Select-String -Path $tunnelLog -Pattern 'https://[a-z0-9-]+\.trycloudflare\.com' | Select-Object -First 1
      if ($match) { $script:publicUrl = $match.Matches[0].Value }
    }
  }
  if (-not $script:publicUrl) { Log 'Tunnel gave no address within 60 s (see tunnel.log)'; return }
  Log "Tunnel address: $($script:publicUrl)"
  # A new quick-tunnel name can take a few seconds to resolve worldwide.
  for ($i = 0; $i -lt 30; $i++) {
    if (Test-Url $script:publicUrl) { Log 'Tunnel is answering'; return }
    Start-Sleep -Seconds 2
  }
  Log 'Tunnel is not answering yet; publishing anyway'
}

function Publish-Url {
  if (-not $script:publicUrl -or $script:publicUrl -eq $script:publishedUrl) { return }
  $payload = @{ files = @{ $GistFile = @{ content = (@{ apiBaseUrl = $script:publicUrl; updatedAt = (Get-Date).ToUniversalTime().ToString('o') } | ConvertTo-Json -Compress) } } } | ConvertTo-Json -Depth 5 -Compress
  $tmp = New-TemporaryFile
  try {
    [IO.File]::WriteAllText($tmp, $payload)
    & $gh api --method PATCH "gists/$GistId" --input $tmp.FullName | Out-Null
    if ($LASTEXITCODE -eq 0) { $script:publishedUrl = $script:publicUrl; Log "Published $($script:publicUrl) to gist $GistId" }
    else { Log "Publishing to the gist failed (gh exit $LASTEXITCODE); will retry" }
  } finally { Remove-Item $tmp -ErrorAction SilentlyContinue }
}

Log "Study Assistant public server starting (repo $repo)"
Start-Api
Start-Tunnel
Publish-Url

$publicFailures = 0
while ($true) {
  Start-Sleep -Seconds $CheckEverySeconds
  if (-not (Test-Url "http://127.0.0.1:$Port")) {
    Log 'API stopped answering; restarting it'
    if ($script:api -and -not $script:api.HasExited) { Stop-Process -Id $script:api.Id -Force -ErrorAction SilentlyContinue }
    Start-Api
  }
  if (-not $script:tunnel -or $script:tunnel.HasExited) {
    Log 'Tunnel process ended; reopening'
    Start-Tunnel
  } elseif ($script:publicUrl -and -not (Test-Url $script:publicUrl)) {
    $publicFailures++
    # Three misses in a row (90 s) before replacing a tunnel: a single miss is usually the network.
    if ($publicFailures -ge 3) { Log 'Tunnel unreachable from outside; reopening'; Start-Tunnel; $publicFailures = 0 }
  } else {
    $publicFailures = 0
  }
  Publish-Url
}
