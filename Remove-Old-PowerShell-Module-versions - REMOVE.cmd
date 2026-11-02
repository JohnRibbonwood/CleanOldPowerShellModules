@echo off
title %~nx0

rem Deleting modules installed for all users (Program Files) needs administrator rights.
rem Restart this file elevated when it isn't. Note: if you elevate with a different
rem (admin) account, that account's own CurrentUser modules are cleaned, not yours.
fltmc >nul 2>&1
if not errorlevel 1 goto :admin
if "%~1"=="elevated" goto :noadmin
echo Requesting administrator rights...
powershell -NoProfile -ExecutionPolicy Bypass -Command "Start-Process -FilePath '%~f0' -ArgumentList 'elevated' -Verb RunAs"
if errorlevel 1 pause
exit /b

:noadmin
echo Could not get administrator rights.
pause
exit /b 1

:admin
cd /d "%~dp0"

echo Removing old PowerShell 5.x module versions
title Removing old PowerShell 5.x module versions
powershell -NoProfile -ExecutionPolicy Bypass -Command ".\Remove-Old-PowerShell-Module-versions.ps1 -TranscriptFolder .\Logging -WhatIf:$false"
pause

where /q pwsh
if errorlevel 1 (
    echo PowerShell 7 ^(pwsh^) not found, skipping the PowerShell 7.x modules.
) else (
    echo Removing old PowerShell 7.x module versions
    title Removing old PowerShell 7.x module versions
    pwsh -NoProfile -ExecutionPolicy Bypass -Command ".\Remove-Old-PowerShell-Module-versions.ps1 -TranscriptFolder .\Logging -WhatIf:$false"
)
pause
