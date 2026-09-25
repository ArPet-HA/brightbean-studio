@echo off
title BrightBean + tunnel + BitAap
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0start-brightbean-tunnel.ps1"
echo.
pause
