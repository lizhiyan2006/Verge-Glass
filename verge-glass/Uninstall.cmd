@echo off
title Verge Glass Uninstaller
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0VergeGlass.ps1" uninstall
echo.
pause
