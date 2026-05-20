# PrepareMigration

A Cursor Agent Skill for Windows that snapshots all Cursor state, user-specific
data, and C-drive project roots to a timestamped folder under a backup root
(default `H:\WorkStationXfer\migrations\`), and a companion script that
restores the latest snapshot to a fresh workstation.

Designed for the case where a workstation is going to be wiped, but persistent
network drives (`H:`, `N:`, etc.) survive. The skill copies only C-drive data
and ignores everything Cursor has open on persistent drives.

## What it captures

- Cursor user state: `%USERPROFILE%\.cursor`, `%APPDATA%\Cursor`
- VS Code user state: `%APPDATA%\Code` (if present)
- User-installed runtimes: `miniconda3`, `miniforge3`, `mambaforge`,
  `anaconda3`, `uv`, `pip`, `Python` under `%APPDATA%` / `%LOCALAPPDATA%`
- User-installed programs: `%LOCALAPPDATA%\Programs`
- User data folders: `Downloads`, `Documents`, `Desktop`, `Pictures`, `Videos`
- User config: `.gitconfig`, `.ssh`, `.aws`, `.azure`, `.kube`, `.npmrc`,
  `.condarc`
- Every C-drive workspace Cursor has touched (discovered from
  `workspaceStorage\*\workspace.json` and `globalStorage\storage.json`)

System Pythons under `C:\Python3xx` and browser caches are deliberately
excluded.

## Install

Personal skill (current user only):

```powershell
git clone https://github.com/<owner>/Bwebb_Skills "$env:USERPROFILE\Bwebb_Skills"
robocopy "$env:USERPROFILE\Bwebb_Skills\PrepareMigration" `
         "$env:USERPROFILE\.cursor\skills\PrepareMigration" `
         /E /COPY:DAT /R:2 /W:2
```

Or copy the `PrepareMigration\` folder directly into
`%USERPROFILE%\.cursor\skills\`.

Restart Cursor (or open a fresh chat) and the skill will be discoverable by
name.

## Usage

In any Cursor chat:

> prepare migration

The agent invokes `scripts\Invoke-PrepareMigration.ps1`. Flags it supports:

| Flag | Purpose |
| --- | --- |
| `-MigrationRoot <path>` | Override the default snapshot root. |
| `-ExtraIncludePaths @('C:\foo','D:\bar')` | Add ad-hoc paths to the snapshot. |
| `-SkipVenv` | Skip `.venv` and `.cache` directories. |
| `-DryRun` | Plan only, no copy. Writes a manifest with `dry_run: true`. |

Direct invocation:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File "$env:USERPROFILE\.cursor\skills\PrepareMigration\scripts\Invoke-PrepareMigration.ps1"
```

## Restore on a new machine

The migration snapshot folder includes a `RESTORE.md` that the new Cursor can
paste into a chat. Alternately, run the restore script directly:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File "<migration_root>\skills\PrepareMigration\scripts\Invoke-RestoreMigration.ps1"
```

Default behavior:

- Looks under `H:\WorkStationXfer\migrations\` for the latest non-dry-run
  snapshot.
- Reads `migration-manifest.json` and copies each item back, expanding
  `%USERPROFILE%`, `%APPDATA%`, and `%LOCALAPPDATA%` against the new
  machine's environment.
- Logs a "USERNAME REMAP NOTICE" if the source user differs from the current
  user. The script still puts files into the correct `%USERPROFILE%`; the
  notice is for spotting tools that may have hardcoded the old name.

Flags:

| Flag | Purpose |
| --- | --- |
| `-SnapshotPath <path>` | Restore a specific snapshot instead of the latest. |
| `-MigrationRoot <path>` | Override the default migration root. |
| `-DryRun` | Plan only, no copy. |

## Exit code policy

Robocopy exit codes:

- `0..7` are success (files copied, nothing failed badly).
- `8..15` are partial — usually means a few files were locked. Robocopy still
  copied the bulk. Cursor's own `AppData\Roaming\Cursor` typically falls here
  when invoking the script from an active Cursor chat.
- `>=16` are fatal — no data copied for that item. Investigate before treating
  the snapshot as complete.

The script aggregates per-item exit codes and surfaces both categories.

## Compatibility

- Windows 10/11 with PowerShell 5.1 or PowerShell 7. The skill's docs show
  `pwsh` first; fall back to `powershell.exe` if `pwsh` is not on PATH.
- Cursor on Windows. Skill placement under `~\.cursor\skills\` is the
  documented personal-skills location. Do not place it under
  `~\.cursor\skills-cursor\`; that directory is reserved for Cursor's managed
  skills.

## Layout

```
PrepareMigration/
  README.md                                    (this file)
  SKILL.md                                     (skill manifest + instructions)
  scripts/
    Invoke-PrepareMigration.ps1                (snapshot writer)
    Invoke-RestoreMigration.ps1                (snapshot restorer)
```
