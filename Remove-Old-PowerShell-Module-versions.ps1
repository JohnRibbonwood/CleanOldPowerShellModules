<#
.SYNOPSIS
    Removes old versions of installed PowerShell modules and keeps only the latest version of each.

.DESCRIPTION
    Lists all installed modules with Get-Module -ListAvailable, groups them per module name
    and keeps the highest version. The ModuleBase directories of all older versions are
    processed in ModuleBase order and deleted.

    WhatIf mode is the DEFAULT: without options the script only shows which old directories
    would be deleted. To really delete them, add -WhatIf:$false.

    Options (all can be combined on one command line):
        -TranscriptFolder <path>  Folder for the transcript log (default: the script's folder).
        (default) / -WhatIf       Show which old directories would be deleted; delete nothing.
        -WhatIf:$false            Delete the old directories.
        -Confirm                  Ask for confirmation before deleting each directory
                                  (only has effect together with -WhatIf:$false).
        -Verbose                  Also show skipped directories and progress messages.

    These are always kept:
      - The latest version of each module (every copy of it).
      - The latest stable version, when the latest version is a prerelease.
      - Versions that a kept module requires exactly: RequiredModules entries with
        RequiredVersion, or the highest installed version allowed by MaximumVersion.
        Example: Az requires exact versions of Az.Storage, Az.Compute and so on, so those
        stay even when a newer Az.Storage is installed on its own.
      - Modules under $PSHOME and the Windows folder, and folders owned by TrustedInstaller
        (copies that ship with Windows, such as Pester 3.4.0).
      - In PowerShell 7: everything in the Windows PowerShell 5.1 module folders, and in
        Windows PowerShell 5.1: everything in the PowerShell 7 module folders. Each edition
        only cleans up its own folders, so one never deletes a version the other still uses.
        Versions that the other edition's modules require exactly are kept as well.
        Run the script in both editions to clean up both.

    Each old folder is first renamed to '<folder>.deleting-<timestamp>' and then deleted.
    If a file in it is in use (module loaded in another PowerShell window, VS Code or a
    service), the rename fails and the folder is left untouched instead of half deleted.
    If deleting fails after the rename, PowerShell no longer sees the renamed folder and
    the next run tries to delete it again.

    Deleting modules in Program Files (installed for all users) needs an elevated session
    (Run as administrator). Without it those folders are left untouched and reported.

    Every run (including -WhatIf runs) is recorded in a transcript named
        <scriptname>-PS<major version>-TRANSCRIPT-<yyyy-MM-dd_HHmmss>.log
    in the script's folder, or in -TranscriptFolder when given. Problems the script handles
    itself (a manifest it can't read, a folder in use) are logged as one WARNING or VERBOSE
    line, never as a "TerminatingError" entry.

.PARAMETER TranscriptFolder
    Folder for the transcript log. Default: the folder this script is in.
    The folder is created if it doesn't exist.

.EXAMPLE
    .\Remove-Old-PowerShell-Module-versions.ps1 -TranscriptFolder C:\Logs -Verbose
    Dry run (default): shows which old module directories would be deleted and which
    were skipped, writes the transcript to C:\Logs, and deletes nothing.

.EXAMPLE
    .\Remove-Old-PowerShell-Module-versions.ps1 -TranscriptFolder C:\Logs -WhatIf:$false -Confirm -Verbose
    Real run with all options: asks before deleting each old module directory, shows
    which directories were skipped, and writes the transcript to C:\Logs.

.EXAMPLE
    .\Remove-Old-PowerShell-Module-versions.ps1 -TranscriptFolder C:\Logs -WhatIf:$false -Verbose
    Real run without prompts: deletes all old module directories, shows which were
    skipped, and writes the transcript to C:\Logs.
#>
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
param(
    [string]$TranscriptFolder = $PSScriptRoot
)

# WhatIf mode is the default: only delete when -WhatIf:$false is given explicitly
if (-not $PSBoundParameters.ContainsKey('WhatIf')) {
    $WhatIfPreference = $true
}

$sep       = [IO.Path]::DirectorySeparatorChar
$onWindows = $env:OS -eq 'Windows_NT'

function Get-NormalizedDir([string]$Path) {
    # Trailing separator so "C:\Mod\Foo" doesn't match "C:\Mod\FooBar"
    return $Path.TrimEnd('\', '/') + $sep
}

function Test-IsUnder([string]$Path, [string[]]$Roots) {
    $p = Get-NormalizedDir $Path
    foreach ($r in $Roots) {
        if ($p.StartsWith($r, [StringComparison]::OrdinalIgnoreCase)) { return $true }
    }
    return $false
}

function Get-Prerelease($Module) {
    # Get-Module reports 3.0.0-preview1 as version 3.0.0; the label is in the manifest's PSData
    return [string]$Module.PrivateData.PSData.Prerelease
}

function ConvertTo-Version([string]$Text) {
    # '1.2.*' -> 1.2.2147483647, '2.0.0-preview1' -> 2.0.0, anything else unparsable -> $null
    $clean = ($Text -replace '-.*$', '') -replace '\*', '2147483647'
    $v = $null
    if ([version]::TryParse($clean, [ref]$v)) { return $v }
    return $null
}

function Get-Requirement($Module) {
    # Exact (RequiredVersion) and upper-bound (MaximumVersion) requirements of a module.
    # Plain names and minimum versions (ModuleVersion) are always met by the latest version.
    #
    # Only the RequiredModules entry of the manifest is evaluated. Many of Windows' own
    # manifests contain code elsewhere (e.g. RootModule = if (...) {...}), which
    # Import-PowerShellDataFile refuses with an error that the transcript logs as
    # "TerminatingError" even when it is caught. The parser and SafeGetValue() are .NET
    # calls, so a failure here is handled quietly and never shows up in the transcript.
    $list = $null
    $read = $false
    if ($Module.Path -like '*.psd1') {
        $parseErrors = $null
        $ast  = [System.Management.Automation.Language.Parser]::ParseFile($Module.Path, [ref]$null, [ref]$parseErrors)
        $hash = $ast.Find({ $args[0] -is [System.Management.Automation.Language.HashtableAst] }, $false)
        if ($hash -and @($parseErrors).Count -eq 0) {
            $pair = $hash.KeyValuePairs | Where-Object { $_.Item1.Value -eq 'RequiredModules' } | Select-Object -First 1
            if (-not $pair) { return }   # no RequiredModules entry: nothing required

            $valueAst = $pair.Item2
            if ($valueAst -is [System.Management.Automation.Language.PipelineAst]) {
                $valueAst = $valueAst.GetPureExpression()
            }
            if ($valueAst) {
                try {
                    $list = $valueAst.SafeGetValue()
                    $read = $true
                }
                catch { }
            }
        }
        if (-not $read) {
            Write-Verbose "RequiredModules in $($Module.Path) is not plain data; using Get-Module's list instead."
        }
    }

    if (-not $read) {
        # Get-Module can't tell exact from minimum versions, so treat every listed
        # version as exact. That keeps more, never less.
        foreach ($r in $Module.RequiredModules) {
            if ($r.Version -and $r.Version -ne [version]'0.0') {
                [pscustomobject]@{ Name = $r.Name; Exact = $r.Version; Max = $null }
            }
        }
        return
    }

    foreach ($r in @($list)) {
        if ($r -isnot [System.Collections.IDictionary]) { continue }   # plain name: any version
        [pscustomobject]@{
            Name  = [string]$r.ModuleName
            Exact = ConvertTo-Version $r.RequiredVersion
            Max   = ConvertTo-Version $r.MaximumVersion
        }
    }
}

function Add-Keep([string]$Name, [version]$Version, [string]$Reason) {
    # Mark a module version as kept, and queue its copies so their requirements are kept too
    $key = "$Name|$Version"
    if ($keep.ContainsKey($key)) { return }
    $keep[$key] = $Reason
    foreach ($m in $byName[$Name]) {
        if ($m.Version -eq $Version) { $queue.Enqueue($m) }
    }
}

# --- Transcript -------------------------------------------------------------
$scriptName     = [IO.Path]::GetFileNameWithoutExtension($PSCommandPath)
$timestamp      = Get-Date -Format 'yyyy-MM-dd_HHmmss'
$transcriptFile = Join-Path $TranscriptFolder "$scriptName-PS$($PSVersionTable.PSVersion.Major)-TRANSCRIPT-$timestamp.log"

# -WhatIf:$false so the transcript is also written during a -WhatIf run.
# If the log can't be written, stop before deleting anything.
try {
    # Windows PowerShell 5.1 doesn't create a missing transcript folder
    New-Item -ItemType Directory -Path $TranscriptFolder -Force -WhatIf:$false -Confirm:$false -ErrorAction Stop | Out-Null
    Start-Transcript -LiteralPath $transcriptFile -WhatIf:$false -Confirm:$false -ErrorAction Stop
}
catch {
    throw "Could not start transcript '$transcriptFile'. Nothing was deleted. Use -TranscriptFolder to pick a writable folder. ($($_.Exception.Message))"
}

try {
    Write-Host "PowerShell $($PSVersionTable.PSVersion) ($($PSVersionTable.PSEdition))"

    if (-not $WhatIfPreference -and $onWindows) {
        $principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
        if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
            Write-Warning 'Not running as administrator: modules installed for all users (Program Files) cannot be deleted and will be left untouched. Run elevated to delete those too.'
        }
    }

    # Modules that ship with PowerShell / Windows are never deleted
    $protectedRoots = @($PSHOME, $env:SystemRoot) |
        Where-Object { $_ } |
        ForEach-Object { Get-NormalizedDir $_ }

    Write-Verbose 'Collecting installed modules...'
    $modules = @(Get-Module -ListAvailable)

    # Each edition only cleans up its own folders. PowerShell 7 also lists the Windows
    # PowerShell 5.1 folders; without this, a newer copy in a PowerShell 7 folder would
    # delete the only copy that Windows PowerShell 5.1 can use (and the other way around).
    $documents = [Environment]::GetFolderPath('MyDocuments')
    if ($PSVersionTable.PSEdition -eq 'Core') {
        $otherEdition = 'Windows PowerShell 5.1'
        $otherRoots   = @(
            if ($env:ProgramFiles) { Join-Path $env:ProgramFiles 'WindowsPowerShell\Modules' }
            if ($documents)        { Join-Path $documents 'WindowsPowerShell\Modules' }
        )
    }
    else {
        $otherEdition = 'PowerShell 7'
        $otherRoots   = @(
            if ($env:ProgramFiles) { Join-Path $env:ProgramFiles 'PowerShell' }
            if ($documents)        { Join-Path $documents 'PowerShell\Modules' }
        )
    }
    $otherModules = @()
    if ($otherRoots.Count -gt 0) {
        $otherRoots   = @($otherRoots | ForEach-Object { Get-NormalizedDir $_ })
        $otherModules = @($modules | Where-Object { Test-IsUnder $_.ModuleBase $otherRoots })
        $modules      = @($modules | Where-Object { -not (Test-IsUnder $_.ModuleBase $otherRoots) })
        Write-Verbose "Left $($otherModules.Count) module(s) in the $otherEdition folders to the $otherEdition run."
    }

    $byName = @{}   # module name -> all installed copies (case-insensitive keys)
    foreach ($group in $modules | Group-Object Name) {
        $byName[$group.Name] = @($group.Group)
    }

    $keep   = @{}   # "name|version" -> reason it is kept
    $queue  = New-Object System.Collections.Queue
    $latest = @{}   # module name -> latest version text, for messages

    # Keep the latest version, and the latest stable one when the latest is a prerelease
    foreach ($name in @($byName.Keys | Sort-Object)) {
        $sorted = @($byName[$name] |
            Sort-Object -Property Version, @{ Expression = { -not (Get-Prerelease $_) } } -Descending)
        $top = $sorted[0]
        $pre = Get-Prerelease $top
        $latest[$name] = if ($pre) { "$($top.Version)-$pre" } else { "$($top.Version)" }
        Add-Keep $name $top.Version 'latest version'

        if ($pre) {
            $stable = $sorted | Where-Object { -not (Get-Prerelease $_) } | Select-Object -First 1
            if ($stable) { Add-Keep $name $stable.Version "latest stable version, $($latest[$name]) is a prerelease" }
        }
    }

    # The other edition's modules aren't deleted here, but PowerShell 7 can also load modules
    # from the 5.1 folders, so what their latest versions require exactly must stay as well
    foreach ($group in $otherModules | Group-Object Name) {
        $queue.Enqueue(($group.Group | Sort-Object Version -Descending | Select-Object -First 1))
    }

    # Keep versions that kept modules require exactly (and what those require, and so on)
    while ($queue.Count -gt 0) {
        $m = $queue.Dequeue()
        foreach ($req in Get-Requirement $m) {
            $installed = $byName[$req.Name]
            if (-not $installed) { continue }
            if ($req.Exact) {
                Add-Keep $req.Name $req.Exact "required by $($m.Name) $($m.Version)"
            }
            elseif ($req.Max) {
                $best = $installed | Where-Object { $_.Version -le $req.Max } |
                    Sort-Object Version -Descending | Select-Object -First 1
                if ($best) { Add-Keep $req.Name $best.Version "highest version allowed by $($m.Name) $($m.Version)" }
            }
        }
    }

    # Collect the old versions
    $toDelete = foreach ($name in @($byName.Keys | Sort-Object)) {
        $group     = $byName[$name]
        $keepBases = @($group | Where-Object { $keep.ContainsKey("$($_.Name)|$($_.Version)") } |
                       Select-Object -ExpandProperty ModuleBase -Unique)

        foreach ($old in $group) {
            $reason = $keep["$($old.Name)|$($old.Version)"]
            if ($reason) {
                if ($reason -ne 'latest version') {
                    Write-Host "Keeping $($old.Name) $($old.Version) ($reason): $($old.ModuleBase)"
                }
                continue
            }

            if (Test-IsUnder $old.ModuleBase $protectedRoots) {
                Write-Verbose "Skipping (system folder): $($old.ModuleBase)"
                continue
            }

            # Never delete a folder that contains (or is) the folder of a version we keep
            $oldRoot = Get-NormalizedDir $old.ModuleBase
            if ($keepBases | Where-Object { Test-IsUnder $_ @($oldRoot) }) {
                Write-Verbose "Skipping (contains a kept version): $($old.ModuleBase)"
                continue
            }

            # Copies that ship with Windows in Program Files (e.g. Pester 3.4.0) are owned by
            # TrustedInstaller; even an administrator can't delete them this way
            if ($onWindows) {
                $acl = Get-Acl -LiteralPath $old.ModuleBase -ErrorAction SilentlyContinue
                if ($acl -and $acl.Owner -like '*\TrustedInstaller') {
                    Write-Verbose "Skipping (owned by Windows / TrustedInstaller): $($old.ModuleBase)"
                    continue
                }
            }

            [pscustomobject]@{
                Name          = $old.Name
                Version       = $old.Version
                LatestVersion = $latest[$name]
                ModuleBase    = $old.ModuleBase
                Leftover      = $false
            }
        }
    }

    # Folders an earlier run renamed but could not delete completely
    $leftovers = foreach ($root in $env:PSModulePath -split [IO.Path]::PathSeparator) {
        if (-not $root -or -not (Test-Path -LiteralPath $root)) { continue }
        if (Test-IsUnder $root $protectedRoots) { continue }
        $dirs = @(Get-ChildItem -LiteralPath $root -Directory -ErrorAction SilentlyContinue)
        $dirs + @($dirs | ForEach-Object { Get-ChildItem -LiteralPath $_.FullName -Directory -ErrorAction SilentlyContinue }) |
            Where-Object { $_.Name -like '*.deleting-*' } |
            ForEach-Object {
                [pscustomobject]@{
                    Name          = '(leftover of an earlier run)'
                    Version       = ''
                    LatestVersion = ''
                    ModuleBase    = $_.FullName
                    Leftover      = $true
                }
            }
    }

    # Order by ModuleBase, one entry per directory
    $toDelete = @(@($toDelete) + @($leftovers) | Where-Object { $_ } | Sort-Object ModuleBase -Unique)

    if ($toDelete.Count -eq 0) {
        Write-Host 'No old module versions found.'
        return
    }

    $deleted   = 0
    $untouched = 0
    $partly    = 0

    foreach ($item in $toDelete) {
        $action = if ($item.Leftover) { "Delete $($item.Name)" }
                  else { "Delete $($item.Name) $($item.Version) (latest is $($item.LatestVersion))" }

        if (-not $PSCmdlet.ShouldProcess($item.ModuleBase, $action)) { continue }

        if (-not (Test-Path -LiteralPath $item.ModuleBase)) {
            Write-Verbose "Already gone (deleted with a parent folder): $($item.ModuleBase)"
            continue
        }

        # Errors below are collected with -ErrorAction SilentlyContinue -ErrorVariable instead
        # of -ErrorAction Stop + try/catch: a caught Stop error is still written to the
        # transcript as "TerminatingError". This way the log only gets our own WARNING line.
        $target = $item.ModuleBase
        if (-not $item.Leftover) {
            # Rename first: this fails, without changing anything, when a file in the folder
            # is in use or we have no access. A plain recursive delete would stop halfway.
            $newName   = "$(Split-Path -Leaf $item.ModuleBase).deleting-$timestamp"
            $renameErr = $null
            Rename-Item -LiteralPath $item.ModuleBase -NewName $newName -Force -Confirm:$false `
                -ErrorAction SilentlyContinue -ErrorVariable renameErr
            if ($renameErr) {
                Write-Warning "Left untouched (in use, or no access): $($item.ModuleBase) ($($renameErr[0].Exception.Message))"
                $untouched++
                continue
            }
            $target = Join-Path (Split-Path -Parent $item.ModuleBase) $newName
        }

        $removeErr = $null
        Remove-Item -LiteralPath $target -Recurse -Force -Confirm:$false `
            -ErrorAction SilentlyContinue -ErrorVariable removeErr
        if (-not $removeErr -and -not (Test-Path -LiteralPath $target)) {
            Write-Host "Deleted: $($item.ModuleBase)"
            $deleted++
        }
        else {
            $why = if ($removeErr) { $removeErr[0].Exception.Message } else { 'folder still exists' }
            if ($item.Leftover) {
                Write-Warning "Could not delete everything in $target yet; the next run tries again. ($why)"
            }
            else {
                Write-Warning "Partly deleted: $($item.ModuleBase). The rest is in '$target'; PowerShell no longer sees it and the next run tries again. ($why)"
            }
            $partly++
        }
    }

    Write-Host ''
    if ($WhatIfPreference) {
        Write-Host "Dry run: $($toDelete.Count) old module directories found, nothing was deleted."
        Write-Host 'Run again with -WhatIf:$false to delete them.'
    }
    else {
        Write-Host "Done. Deleted: $deleted  Left untouched: $untouched  Partly deleted: $partly"
    }
}
finally {
    # Runs on normal end, on 'return', on errors and on Ctrl+C.
    # WhatIf/Confirm off so -WhatIf and -Confirm runs close the log without a prompt
    # (5.1 has no -WhatIf/-Confirm on Stop-Transcript, so set the preferences instead).
    $WhatIfPreference  = $false
    $ConfirmPreference = 'None'
    Stop-Transcript | Out-Null
}
