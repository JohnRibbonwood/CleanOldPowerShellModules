@echo off
title %~nx0

cd /d "%~dp0"

powershell -NoProfile -ExecutionPolicy Bypass -File ".\PowerShell list all installed Modules.ps1"

where /q pwsh
if not errorlevel 1 pwsh -NoProfile -ExecutionPolicy Bypass -File ".\PowerShell list all installed Modules.ps1"

pause
