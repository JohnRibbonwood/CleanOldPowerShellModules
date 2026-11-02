@echo off
title %~nx0

cd /d "%~dp0"

pwsh -NoProfile -ExecutionPolicy Bypass -Command "Install-module az.accounts -RequiredVersion 2.2.3 -force"
pwsh -NoProfile -ExecutionPolicy Bypass -Command "Install-module az.accounts -RequiredVersion 2.2.4 -force"
pwsh -NoProfile -ExecutionPolicy Bypass -Command "Install-module az.accounts -RequiredVersion 2.2.5 -force"
pwsh -NoProfile -ExecutionPolicy Bypass -Command "Install-module az.accounts -RequiredVersion 2.2.6 -force"
pwsh -NoProfile -ExecutionPolicy Bypass -Command "Install-module az.accounts -RequiredVersion 2.2.7 -force"

pause
