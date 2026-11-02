@echo off
title %~nx0

cd /d "%~dp0"

powershell -NoProfile -ExecutionPolicy Bypass -Command "Install-Module -Name VMware.Vim -RequiredVersion 9.1.0.25718932 -SkipPublisherCheck -Force -AllowClobber -Verbose"

powershell -NoProfile -ExecutionPolicy Bypass -Command "Install-Module -Name VMware.Vim -RequiredVersion 9.1.0.25380678 -SkipPublisherCheck -Force -AllowClobber -Verbose"

pause
