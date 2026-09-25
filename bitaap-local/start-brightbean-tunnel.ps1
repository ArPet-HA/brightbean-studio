# Starts BrightBean Studio (Docker) with a public, media-only tunnel so Meta can fetch images,
# points BrightBean's APP_URL at that tunnel, and optionally starts BitAap Growth OS.
# Only /media/... is public. The BrightBean app itself stays on http://localhost:8000.
# 'Continue': docker writes progress to stderr, which PowerShell 5.1 would otherwise treat as fatal.
# Failures are detected via $LASTEXITCODE and explicit throws.
$ErrorActionPreference = 'Continue'
$here = $PSScriptRoot
$bb = Split-Path $here -Parent
$bitaapStart = Join-Path (Split-Path $bb -Parent) 'BitAap Growth OS\Start BitAap lokaal.cmd'
$network = 'brightbeanstudio_default'
$override = Join-Path $here 'tunnel.override.yml'
Set-Location $bb

function Step($text) { Write-Host ''; Write-Host "==> $text" -ForegroundColor Cyan }

Step 'Docker controleren'
docker info *> $null
if ($LASTEXITCODE) { throw 'Docker Desktop draait niet. Start Docker Desktop en probeer opnieuw.' }

if (-not (Test-Path (Join-Path $bb '.env'))) { throw 'BrightBean\.env ontbreekt. Kopieer .env.example naar .env en vul minimaal SECRET_KEY, ENCRYPTION_KEY_SALT en de PLATFORM_FACEBOOK_* waarden in (zie bitaap-local\README.md).' }
docker image inspect brightbeanstudio-app *> $null
if ($LASTEXITCODE) {
  Step 'Docker-image bouwen (eenmalig, duurt een paar minuten)'
  docker compose -f docker-compose.yml -f docker-compose.override.yml build app
  if ($LASTEXITCODE) { throw 'Image bouwen mislukte.' }
}

Step 'Database starten'
docker compose -f docker-compose.yml -f docker-compose.override.yml up -d postgres
if ($LASTEXITCODE) { throw 'Database starten mislukte.' }

Step 'Mediaserver en tunnel starten'
docker rm -f bb-media bb-media-tunnel *> $null
docker run -d --name bb-media --network $network -e BIND=0.0.0.0 -v brightbeanstudio_media_data:/data/media:ro -v "${here}:/srv:ro" --entrypoint python brightbeanstudio-app /srv/bb_media_server.py /data/media 8001 | Out-Null
if ($LASTEXITCODE) { throw 'Mediaserver starten mislukte (bestaat de image brightbeanstudio-app? Draai eenmaal docker compose build).' }
docker run -d --name bb-media-tunnel --network $network cloudflare/cloudflared:latest tunnel --no-autoupdate --url http://bb-media:8001 | Out-Null
if ($LASTEXITCODE) { throw 'Tunnel starten mislukte.' }
$url = $null
for ($i = 0; $i -lt 30 -and -not $url; $i++) {
  Start-Sleep -Seconds 2
  $m = (docker logs bb-media-tunnel 2>&1 | Out-String) | Select-String -Pattern 'https://[a-z0-9-]+\.trycloudflare\.com'
  if ($m) { $url = $m.Matches[0].Value }
}
if (-not $url) { throw 'Geen tunneladres ontvangen van Cloudflare. Bekijk: docker logs bb-media-tunnel' }
Write-Host "Tunnel: $url"

Step 'BrightBean starten met APP_URL = tunnel'
$yaml = "services:`n  app:`n    environment:`n      - APP_URL=$url`n  worker:`n    environment:`n      - APP_URL=$url`n"
[IO.File]::WriteAllText($override, $yaml, (New-Object Text.UTF8Encoding $false))
docker compose -f docker-compose.yml -f docker-compose.override.yml -f $override up -d
if ($LASTEXITCODE) { throw 'BrightBean starten mislukte.' }

Step 'Controleren'
$api = 0
for ($i = 0; $i -lt 40 -and $api -ne 401; $i++) {
  Start-Sleep -Seconds 3
  try { Invoke-WebRequest -UseBasicParsing -TimeoutSec 5 http://localhost:8000/api/v1/accounts/ | Out-Null; $api = 200 }
  catch { if ($_.Exception.Response) { $api = [int]$_.Exception.Response.StatusCode } }
}
if ($api -ne 401) { throw "BrightBean-API reageert niet zoals verwacht (status $api)." }
docker exec brightbeanstudio-app-1 sh -c 'echo ok > /app/media/_tunnel_check.txt' | Out-Null
$ok = $false
for ($i = 0; $i -lt 10 -and -not $ok; $i++) {
  Start-Sleep -Seconds 3
  try { $ok = (Invoke-WebRequest -UseBasicParsing -TimeoutSec 15 "$url/media/_tunnel_check.txt").Content.Trim() -eq 'ok' } catch { }
}
docker exec brightbeanstudio-app-1 rm -f /app/media/_tunnel_check.txt | Out-Null
if (-not $ok) { throw 'Media zijn niet bereikbaar via de tunnel. Facebook/Instagram met afbeelding zullen mislukken.' }
$appUrl = (docker exec brightbeanstudio-worker-1 printenv APP_URL).Trim()
if ($appUrl -ne $url) { throw "Worker gebruikt een ander APP_URL ($appUrl)." }

Write-Host ''
Write-Host 'Klaar.' -ForegroundColor Green
Write-Host '  BrightBean:  http://localhost:8000'
Write-Host "  Media-tunnel: $url  (alleen /media/)"
Write-Host '  Laat de computer aan (geen slaapstand) tot ingeplande social posts zijn verstuurd.'

$bitaapUp = Get-NetTCPConnection -LocalPort 3100 -State Listen -ErrorAction SilentlyContinue
if (-not $bitaapUp -and (Test-Path $bitaapStart)) {
  Step 'BitAap Growth OS starten'
  Start-Process -FilePath $bitaapStart -WorkingDirectory (Split-Path $bitaapStart -Parent)
} elseif ($bitaapUp) {
  Write-Host '  BitAap draait al op http://localhost:3100'
}
