# Writes all installed PowerShell modules (name, version, folder) to a text file in the
# Logging subfolder next to this script. No administrator rights needed. Run it in both
# Windows PowerShell 5.1 and PowerShell 7 to get both lists (the .cmd file does that).

Write-Host "Getting all installed PowerShell modules (PowerShell $($PSVersionTable.PSVersion))..." -ForegroundColor Yellow

$logFolder = Join-Path $PSScriptRoot 'Logging'
New-Item -ItemType Directory -Path $logFolder -Force | Out-Null

$file = Join-Path $logFolder "Installed_PowerShell_Modules_$($env:COMPUTERNAME)_PS$($PSVersionTable.PSVersion.Major)_$(Get-Date -Format 'yyyy-MM-dd_HHmmss').txt"
Get-Module -ListAvailable | Sort-Object Name, Version | Select-Object Name, Version, ModuleBase |
    Format-Table -AutoSize | Out-File -FilePath $file -Width 500 -Encoding utf8

Write-Host "Results written to: $file" -ForegroundColor Yellow
