Write-Host "Check if logged on as Administrator" -ForegroundColor Yellow

# Abort if not running as Administrator
$principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Error "This script must be run as Administrator. Aborting."
    Start-Sleep -Seconds 4
    exit 1
} else {
    Write-Host "Logged on as Administrator" -ForegroundColor Yellow
}


#
Write-Host "Set-ExecutionPolicy RemoteSigned -Scope CurrentUser -Force" -ForegroundColor Yellow
#
# The .cmd starts this script with -ExecutionPolicy Bypass. Set-ExecutionPolicy then still saves
# RemoteSigned, but reports an 'overridden by a more specific scope' error; that one is expected.
try {
    Set-ExecutionPolicy RemoteSigned -Scope CurrentUser -Force -ErrorAction Stop
}
catch {
    if ($_.FullyQualifiedErrorId -notlike 'ExecutionPolicyOverride*') { throw }
}
Write-Host "Execution policy for CurrentUser is now: $(Get-ExecutionPolicy -Scope CurrentUser)" -ForegroundColor Yellow


#
Write-Host "Enable TLS 1.2 (needed for the PowerShell Gallery)" -ForegroundColor Yellow
#
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
Add-Type -AssemblyName System.IO.Compression.FileSystem

$dest = Join-Path $env:ProgramFiles 'WindowsPowerShell\Modules'
$pkgs = [ordered]@{ PackageManagement = '1.4.8.1'; PowerShellGet = '2.2.5' }

foreach ($name in $pkgs.Keys) {
    $ver = $pkgs[$name]
    $zip = Join-Path $env:TEMP "$name.$ver.zip"
    $out = Join-Path $dest "$name\$ver"
    $tmp = "$out.download"    # same drive as the destination, and not a version folder PowerShell would load

    Write-Host "Download and install $name $ver" -ForegroundColor Yellow
    (New-Object Net.WebClient).DownloadFile("https://www.powershellgallery.com/api/v2/package/$name/$ver", $zip)

    if (Test-Path -LiteralPath $tmp) { Remove-Item -LiteralPath $tmp -Recurse -Force }
    [IO.Compression.ZipFile]::ExtractToDirectory($zip, $tmp)
    Remove-Item -LiteralPath $zip -Force
    Remove-Item -LiteralPath "$tmp\_rels","$tmp\package","$tmp\[Content_Types].xml","$tmp\$name.nuspec" -Recurse -Force -ErrorAction SilentlyContinue

    # Every signed file must carry a valid Microsoft signature; anything else means the
    # download was changed, so don't install it
    $signatures = @(Get-ChildItem -LiteralPath $tmp -Recurse -File |
        Where-Object { '.psd1', '.psm1', '.ps1', '.dll' -contains $_.Extension } |
        ForEach-Object { Get-AuthenticodeSignature -LiteralPath $_.FullName })
    $bad = @($signatures | Where-Object {
        $_.Status -ne 'NotSigned' -and
        ($_.Status -ne 'Valid' -or $_.SignerCertificate.Subject -notlike '*O=Microsoft Corporation*')
    })
    if ($bad.Count -gt 0) {
        Remove-Item -LiteralPath $tmp -Recurse -Force
        $list = ($bad | ForEach-Object { "  $($_.Status)  $($_.Path)" }) -join [Environment]::NewLine
        throw "Signature check failed for $name $ver, nothing installed:$([Environment]::NewLine)$list"
    }
    $valid = @($signatures | Where-Object { $_.Status -eq 'Valid' }).Count
    if ($valid -eq 0) {
        Write-Warning "$name $ver contains no signed files, so it could not be verified."
    }
    else {
        Write-Host "Signature check OK ($valid signed files)" -ForegroundColor Yellow
    }

    if (Test-Path -LiteralPath $out) { Remove-Item -LiteralPath $out -Recurse -Force }
    Rename-Item -LiteralPath $tmp -NewName $ver
}


#
Write-Host "Import module PackageManagement" -ForegroundColor Yellow
#
Import-Module (Join-Path $dest 'PackageManagement\1.4.8.1\PackageManagement.psd1')


#
Write-Host "Import module PowerShellGet" -ForegroundColor Yellow
#
Import-Module (Join-Path $dest 'PowerShellGet\2.2.5\PowerShellGet.psd1')


#
Write-Host "Check the machine PSModulePath" -ForegroundColor Yellow
#
# The two Windows PowerShell folders must come first. Windows' default value already does
# that, so normally nothing is written. When it does need fixing, the value is written
# unexpanded (%ProgramFiles%, %SystemRoot%) as REG_EXPAND_SZ, the same way Windows stores it.
$required = @('%ProgramFiles%\WindowsPowerShell\Modules', '%SystemRoot%\system32\WindowsPowerShell\v1.0\Modules')
$regPath  = 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Environment'
$raw      = [string](Get-Item -LiteralPath $regPath).GetValue('PSModulePath', '', 'DoNotExpandEnvironmentNames')
$entries  = @($raw -split ';' | Where-Object { $_ })

function Expand-PathEntry([string]$Path) {
    [Environment]::ExpandEnvironmentVariables($Path).TrimEnd('\')
}
$requiredExpanded = @($required | ForEach-Object { Expand-PathEntry $_ })

$inOrder = $entries.Count -ge $required.Count
for ($i = 0; $inOrder -and $i -lt $required.Count; $i++) {
    if ((Expand-PathEntry $entries[$i]) -ne $requiredExpanded[$i]) { $inOrder = $false }
}

if ($inOrder) {
    Write-Host "PSModulePath is already correct, not changed." -ForegroundColor Yellow
}
else {
    $rest = @($entries | Where-Object { $requiredExpanded -notcontains (Expand-PathEntry $_) })
    $new  = ($required + $rest) -join ';'
    Set-ItemProperty -LiteralPath $regPath -Name PSModulePath -Value $new -Type ExpandString

    # Tell running programs (Explorer) that the environment changed, so new windows get it
    if (-not ('Win32.EnvironmentBroadcast' -as [type])) {
        Add-Type -Namespace Win32 -Name EnvironmentBroadcast -MemberDefinition @'
[DllImport("user32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
public static extern IntPtr SendMessageTimeout(IntPtr hWnd, uint Msg, UIntPtr wParam, string lParam, uint fuFlags, uint uTimeout, out UIntPtr lpdwResult);
'@
    }
    $result = [UIntPtr]::Zero
    [void][Win32.EnvironmentBroadcast]::SendMessageTimeout([IntPtr]0xffff, 0x1A, [UIntPtr]::Zero, 'Environment', 2, 5000, [ref]$result)

    Write-Host "PSModulePath changed to: $new" -ForegroundColor Yellow
}
