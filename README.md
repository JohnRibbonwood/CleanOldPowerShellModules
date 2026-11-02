
# Clean Old PowerShell Modules

## ⚠️ Disclaimer: Alpha Release

This software is currently in **alpha**. It is experimental, under active development, and not intended for production use.

- Features may be incomplete, unstable, or removed without notice.
- Breaking changes may occur between versions without a migration path.
- Bugs, security issues, and data loss are possible.

This software is provided **"as is"**, without warranty of any kind, express or implied, including but not limited to the warranties of merchantability, fitness for a particular purpose, and non-infringement. In no event shall the author(s) be liable for any claim, damages, or other liability, whether in an action of contract, tort, or otherwise, arising from, out of, or in connection with the software or its use.

**Use at your own risk.** Always back up your data and test thoroughly before relying on this software.

Removes old versions of installed PowerShell modules and keeps only the latest version of each,
for both **Windows PowerShell 5.1** and **PowerShell 7**.

Every `Install-Module` / `Update-Module` adds a new version folder next to the old ones, so module
folders slowly fill up with versions nobody uses. This script finds those old versions and deletes
them, while making sure nothing that is still needed gets removed.

**By default it only shows what it would delete. It deletes only when you explicitly tell it to.**

Tested on Windows (build 26300) with Windows PowerShell 5.1.26100 and PowerShell 7.6.9.

---

## Quick start

1. Double-click **`Remove-Old-PowerShell-Module-versions - SHOW only.cmd`**
   Runs a dry run in Windows PowerShell 5.1, then in PowerShell 7, and shows which folders would be
   deleted. Nothing is deleted. No administrator rights needed.
2. Check the list on screen, or in the transcripts in the `Logging` folder.
3. Double-click **`Remove-Old-PowerShell-Module-versions - REMOVE.cmd`**
   Asks for administrator rights (UAC prompt), then deletes the old versions for Windows
   PowerShell 5.1. Press a key to continue with PowerShell 7. If you decline the UAC prompt,
   nothing runs.

If PowerShell 7 (`pwsh`) isn't installed, both `.cmd` files skip the PowerShell 7 step.

---

## Folder contents

| Path | What it is |
|---|---|
| `Remove-Old-PowerShell-Module-versions.ps1` | The script that does the work. |
| `Remove-Old-PowerShell-Module-versions - SHOW only.cmd` | Dry run in 5.1 and 7. Deletes nothing. |
| `Remove-Old-PowerShell-Module-versions - REMOVE.cmd` | Real run in 5.1 and 7. Restarts itself as administrator. |
| `Logging\` | A transcript of every run (created automatically). |
| `List\PowerShell list all installed Modules.cmd` / `.ps1` | Writes all installed modules to a text file in `List\Logging\`. |
| `Install\Install-Install-Module-for-Version5\` | Installs PowerShellGet 2.2.5 and PackageManagement 1.4.8.1 for Windows PowerShell 5.1. |
| `Install\Install-Dummy-Modules-for-Version5-and-Version7\` | Installs old module versions to test the script with. |
| `README.md` | This file. |

All `.cmd` files start PowerShell with `-NoProfile -ExecutionPolicy Bypass`, so they also work on
PCs where running scripts is blocked, and your PowerShell profile can't load (and lock) modules
during the run.

---

## What is never deleted

| Kept | Why |
|---|---|
| The **latest version** of each module, every copy of it | That's the point. If the same version is installed twice (for all users and in Documents), both copies stay. |
| The **latest stable version** when the latest version is a prerelease | `Get-Module` reports `3.0.0-preview1` as `3.0.0`; without this, installing a preview would delete your stable version. |
| Versions another kept module **requires exactly** (`RequiredVersion` in `RequiredModules`) | E.g. `Az` requires exact versions of `Az.Storage`, `Az.Compute`, ... Updating one of those on its own would otherwise make `Import-Module Az` fail. Followed through all levels. |
| The highest version allowed by a **`MaximumVersion`** requirement | Same reason. |
| Modules under **`$PSHOME`** and the **Windows folder** | They ship with PowerShell / Windows (`C:\Windows\System32\WindowsPowerShell\v1.0\Modules`, `C:\Program Files\PowerShell\7\Modules`). |
| Folders owned by **TrustedInstaller** | Copies that ship with Windows in Program Files, such as Pester 3.4.0. Windows doesn't allow deleting them this way. |
| A folder that **contains** a kept version | Old-style modules without a version folder can contain the newer version folders. |
| **The other edition's module folders** (see below) | So one edition never deletes a version the other still uses. |

Versions kept because something requires them, or because the latest version is a prerelease, are
listed in the output with the reason:

```
Keeping <module> <version> (required by <module> <version>): <folder>
Keeping <module> <version> (latest stable version, <version>-<label> is a prerelease): <folder>
```

### Windows PowerShell 5.1 and PowerShell 7

PowerShell 7 also sees the Windows PowerShell 5.1 module folders. To avoid PowerShell 7 deleting the
only copy that 5.1 can use, **each edition only cleans up its own folders**:

| Run in | Cleans | Leaves alone |
|---|---|---|
| Windows PowerShell 5.1 | `C:\Program Files\WindowsPowerShell\Modules`, `Documents\WindowsPowerShell\Modules` | the PowerShell 7 folders |
| PowerShell 7 | `C:\Program Files\PowerShell\Modules`, `Documents\PowerShell\Modules` | the Windows PowerShell 5.1 folders |

Versions that modules in the other edition's folders require exactly are kept as well. Run the
script in both editions to clean up both; the `.cmd` files do that for you.

Example from a real run: PowerShell 7 saw three copies of Az.Accounts.

| Version | Folder | Result |
|---|---|---|
| 2.2.3 | `C:\Program Files\WindowsPowerShell\Modules\Az.Accounts\2.2.3` | Left alone: Windows PowerShell 5.1 folder (its only copy for 5.1). |
| 2.2.7 | `C:\Users\<user>\Documents\PowerShell\Modules\Az.Accounts\2.2.7` | Deleted: older than 5.5.3. |
| 5.5.3 | `C:\Users\<user>\Documents\PowerShell\Modules\Az.Accounts\5.5.3` | Kept: latest. |

---

## How deleting works

1. Each old version folder is first **renamed** to `<folder>.deleting-<timestamp>`.
   If any file in it is in use (module loaded in another PowerShell window, VS Code, a service) or
   you have no access, the rename fails and the folder is **left untouched**, instead of ending up
   half deleted.
2. The renamed folder is then deleted.
3. If deleting fails partway, the rest stays in the `.deleting-...` folder. PowerShell no longer
   sees it as a module, and **the next run tries to delete it again**.

Modules installed for all users (Program Files) need administrator rights to delete. In a real run
without them, the script warns at the start and reports those folders as "left untouched".

---

## Running the script directly

```powershell
.\Remove-Old-PowerShell-Module-versions.ps1 [-TranscriptFolder <path>] [-WhatIf:$false] [-Confirm] [-Verbose]
```

| Option | Effect |
|---|---|
| *(none)* or `-WhatIf` | **Default.** Shows what would be deleted; deletes nothing. |
| `-WhatIf:$false` | Really deletes. |
| `-Confirm` | Asks before each folder (only with `-WhatIf:$false`). |
| `-Verbose` | Also shows skipped folders and why (system folder, owned by Windows, other edition, ...). The `.cmd` files don't use it. |
| `-TranscriptFolder <path>` | Where the transcript goes. Default: the script's folder. Created if missing. |

Examples:

```powershell
# Dry run, transcript to C:\Logs, show skipped folders
.\Remove-Old-PowerShell-Module-versions.ps1 -TranscriptFolder C:\Logs -Verbose

# Real run, ask before each folder
.\Remove-Old-PowerShell-Module-versions.ps1 -TranscriptFolder C:\Logs -WhatIf:$false -Confirm -Verbose

# Real run without prompts
.\Remove-Old-PowerShell-Module-versions.ps1 -TranscriptFolder C:\Logs -WhatIf:$false
```

Start it from `powershell.exe` for the 5.1 modules and from `pwsh.exe` for the PowerShell 7 modules.
This is what the `.cmd` files run:

```
powershell -NoProfile -ExecutionPolicy Bypass -Command ".\Remove-Old-PowerShell-Module-versions.ps1 -TranscriptFolder .\Logging"
pwsh       -NoProfile -ExecutionPolicy Bypass -Command ".\Remove-Old-PowerShell-Module-versions.ps1 -TranscriptFolder .\Logging"
```

(`REMOVE.cmd` adds `-WhatIf:$false`.)

---

## Transcripts

Every run, including dry runs, writes a transcript:

```
Logging\Remove-Old-PowerShell-Module-versions-PS<5|7>-TRANSCRIPT-<yyyy-MM-dd_HHmmss>.log
```

`PS5` = Windows PowerShell 5.1, `PS7` = PowerShell 7. If the transcript can't be started, the
script stops before deleting anything.

A transcript has three parts:

1. **Header** written by PowerShell: start time, user, PowerShell version and the
   `Host Application` line with the exact command. That line shows whether it was a dry run or a
   real run: only a real run has `-WhatIf:$false`.
2. **The script's output**, starting with the PowerShell version it ran in.
3. **Footer** with the end time.

Real examples (header and footer left out):

Dry run in PowerShell 7 (`SHOW only.cmd`):

```
PowerShell 7.6.9 (Core)
What if: Performing the operation "Delete Az.Accounts 2.2.7 (latest is 5.5.3)" on target "C:\Users\<user>\Documents\PowerShell\Modules\Az.Accounts\2.2.7".

Dry run: 1 old module directories found, nothing was deleted.
Run again with -WhatIf:$false to delete them.
```

Real run in PowerShell 7 (`REMOVE.cmd`):

```
PowerShell 7.6.9 (Core)
Deleted: C:\Users\<user>\Documents\PowerShell\Modules\Az.Accounts\2.2.7

Done. Deleted: 1  Left untouched: 0  Partly deleted: 0
```

Nothing to clean up (here in Windows PowerShell 5.1):

```
PowerShell 5.1.26100.9711 (Desktop)
No old module versions found.
```

### What each line means

| Line | Meaning |
|---|---|
| `PowerShell <version> (Desktop\|Core)` | Which edition this run is for: `Desktop` = 5.1, `Core` = 7. |
| `Keeping <module> <version> (<reason>): <folder>` | Older version kept on purpose (see "What is never deleted"). |
| `What if: ... "Delete <module> <version> (latest is <x>)" on target "<folder>"` | Dry run: this folder would be deleted. |
| `What if: ... "Delete (leftover of an earlier run)" ...` | Dry run: a `.deleting-...` folder from an earlier run would be removed. |
| `Deleted: <folder>` | Deleted. |
| `WARNING: Not running as administrator: ...` | Real run without admin rights; Program Files modules will be left untouched. |
| `WARNING: Left untouched (in use, or no access): <folder> (<reason>)` | Couldn't rename it; nothing was changed. Close other PowerShell windows / VS Code, or run as administrator, and try again. |
| `WARNING: Partly deleted: <folder>. The rest is in '<folder>.deleting-...'` | Renamed, but not everything could be deleted. The next run finishes it. |
| `WARNING: Could not delete everything in <folder>.deleting-... yet` | A leftover from an earlier run is still (partly) in use. The next run tries again. |
| `Dry run: n old module directories found, nothing was deleted.` | Summary of a dry run. |
| `Done. Deleted: n  Left untouched: n  Partly deleted: n` | Summary of a real run. |
| `No old module versions found.` | Nothing to do. |
| `VERBOSE: ...` | Only with `-Verbose`: skipped folders, progress, manifests it couldn't read. |

Problems the script handles itself (a manifest it can't read, a folder in use) appear as one
`WARNING:` or `VERBOSE:` line. They don't show up as `TerminatingError` entries.

---

## Helper scripts

### List all installed modules

`List\PowerShell list all installed Modules.cmd` runs the list script in Windows PowerShell 5.1 and
(if installed) PowerShell 7. Each run writes a table of name, version and folder, sorted by name and
version, to

```
List\Logging\Installed_PowerShell_Modules_<COMPUTERNAME>_PS<5|7>_<yyyy-MM-dd_HHmmss>.txt
```

Use it to check the result before and after a clean-up. No administrator rights needed.

### Install PowerShellGet for Windows PowerShell 5.1

`Install\Install-Install-Module-for-Version5\Powershell5-install-Install-Module.cmd` makes
`Install-Module` work properly in Windows PowerShell 5.1. Run it as administrator; otherwise it
stops right away.

- Sets the execution policy for the current user to `RemoteSigned`.
- Enables TLS 1.2, which the PowerShell Gallery requires.
- Downloads **PackageManagement 1.4.8.1** and **PowerShellGet 2.2.5** from the PowerShell Gallery
  into `C:\Program Files\WindowsPowerShell\Modules`. Before installing, every signed file must carry
  a valid Microsoft signature; otherwise nothing is installed.
- Checks that the two Windows PowerShell module folders come first in the machine `PSModulePath`,
  and only changes it if they don't.

### Test modules

`Install\Install-Dummy-Modules-for-Version5-and-Version7\` installs old versions to test with:

| File | Installs | Expected in the `SHOW only` dry run |
|---|---|---|
| `Powershell5-install-previous-VMware.Vim-module.cmd` | VMware.Vim 9.1.0.25718932 and 9.1.0.25380678 in Windows PowerShell 5.1 | The PS5 run lists the older VMware.Vim (unless something requires it exactly). |
| `Powershell7-install-previous-Az.Account-modules.cmd` | Az.Accounts 2.2.3 to 2.2.7 in PowerShell 7 | The PS7 run lists every version except the newest Az.Accounts. |
| `Powershell5-and-7-install-cross-edition-test.cmd` (run as administrator) | Az.Accounts 2.2.3 for 5.1 *for all users*, and 2.2.7 for PowerShell 7 | The PS7 run does **not** list `C:\Program Files\WindowsPowerShell\Modules\Az.Accounts\2.2.3`. |

---

## Requirements

- Windows with Windows PowerShell 5.1. PowerShell 7 is optional.
- Administrator rights to delete modules installed for all users (Program Files).
  Dry runs and modules in your own Documents folder don't need them.

---

## Things to know

- **Same version installed twice.** If a module version is installed both for all users and in
  your Documents folder, both copies are kept. The script only removes *older* versions.
- **Elevating with a different account.** `REMOVE.cmd` runs as the account that approves the UAC
  prompt. If that's a separate admin account, *that* account's Documents modules are cleaned, not
  yours. To clean your own, run the script yourself without elevation (see "Running the script
  directly") with `-WhatIf:$false`.
- **OneDrive.** If your Documents folder is synced by OneDrive, deleting modules there also deletes
  them on your other PCs that sync the same folder.
- **A second run can find more.** When a module folder has version subfolders, PowerShell ignores
  an old-style manifest placed directly in the module folder. Once the version folders are gone,
  that old copy becomes visible and the next run removes it.
- **Requirements with code in them.** If a manifest's `RequiredModules` isn't plain data, the script
  uses the list from `Get-Module` and treats every version in it as required exactly. That can
  keep a version that isn't strictly needed, never the other way around.
- **Custom module folders.** Folders you added to `PSModulePath` yourself are seen by both editions
  and are cleaned by both runs, each comparing against its own module folders.
