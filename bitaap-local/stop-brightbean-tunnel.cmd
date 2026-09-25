@echo off
title BrightBean + tunnel stoppen
cd /d "%~dp0.."
echo Tunnel en mediaserver stoppen...
docker rm -f bb-media bb-media-tunnel >nul 2>&1
echo BrightBean-containers stoppen (data blijft bewaard in de Docker-volumes)...
docker compose -f docker-compose.yml -f docker-compose.override.yml stop
echo.
echo Klaar.
pause
