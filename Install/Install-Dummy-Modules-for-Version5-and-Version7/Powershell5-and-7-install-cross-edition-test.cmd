@echo off
title %~nx0

rem Test for the PowerShell 5.1 / 7 overlap. Run as administrator.
rem
rem Installs an OLD Az.Accounts for Windows PowerShell 5.1 for all users (Program Files,
rem a folder PowerShell 7 can see too) and a NEWER Az.Accounts for PowerShell 7.
rem
rem Expected result of "Remove-Old-PowerShell-Module-versions - SHOW only.cmd":
rem   - the PowerShell 7 run does NOT list the 5.1 copy
rem     (C:\Program Files\WindowsPowerShell\Modules\Az.Accounts\2.2.3);
rem   - the PowerShell 5.1 run does not list it either, because it is the only 5.1 copy.

cd /d "%~dp0"

powershell -NoProfile -ExecutionPolicy Bypass -Command "Install-Module -Name Az.Accounts -RequiredVersion 2.2.3 -Scope AllUsers -Force -Verbose"
pwsh -NoProfile -ExecutionPolicy Bypass -Command "Install-Module -Name Az.Accounts -RequiredVersion 2.2.7 -Scope CurrentUser -Force -Verbose"

pause
