@echo off
title %~nx0

cd /d "%~dp0"

echo Searching for PowerShell 5.x modules
title Searching for PowerShell 5.x modules
powershell -NoProfile -ExecutionPolicy Bypass -Command ".\Remove-Old-PowerShell-Module-versions.ps1 -TranscriptFolder .\Logging"

echo.

where /q pwsh
if errorlevel 1 (
    echo PowerShell 7 ^(pwsh^) not found, skipping the PowerShell 7.x modules.
) else (
    echo Searching for PowerShell 7.x modules
    title Searching for PowerShell 7.x modules
    pwsh -NoProfile -ExecutionPolicy Bypass -Command ".\Remove-Old-PowerShell-Module-versions.ps1 -TranscriptFolder .\Logging"
)

pause
