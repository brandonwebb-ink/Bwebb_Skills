---
name: prepare-migration
description: Use to prepare a versioned migration snapshot of all Cursor state, user-specific data, and C-drive project roots on H:\WorkStationXfer for transfer to a wiped or new Windows workstation. Use when the user says "prepare migration", "back up cursor for transfer", or before a workstation wipe.
disable-model-invocation: true
---

# Prepare Migration

Use this skill to snapshot every C-drive thing the user cares about into a timestamped folder under `H:\WorkStationXfer\migrations\`. Persistent drives (`H:`, `N:`) are not copied because they survive the workstation reset.

## When To Run

- User says "prepare migration" or "back up cursor for transfer".
- Before a workstation wipe.
- Periodically as a snapshot of cursor + user data.

## Procedure

1. Tell the user to close all other Cursor windows. The one running this skill keeps running; robocopy retries handle the locked transcript file for the active chat.
2. Confirm `H:\WorkStationXfer` exists.
3. Run the worker script. It does discovery, copy, and manifest write in one pass:

```powershell
pwsh -NoProfile -File "$env:USERPROFILE\.cursor\skills\PrepareMigration\scripts\Invoke-PrepareMigration.ps1"
```

If `pwsh` is unavailable, use `powershell.exe` instead.

4. The script prints `MIGRATION_SNAPSHOT_READY: <snapshot_path>` on success and lists any item with robocopy exit code >= 8. Report that summary back to the user.

5. If any item failed (exit code >= 8), surface the failing source paths and ask the user whether to retry just those items or proceed. Do not silently ignore failures.

## What The Script Does

Discovery:

- Enumerates `%APPDATA%\Cursor\User\workspaceStorage\*\workspace.json` and `%APPDATA%\Cursor\User\globalStorage\storage.json` to find every workspace Cursor knows about.
- Decodes each `file:///` URI to a local path.
- Splits into C-drive paths (to be copied) and persistent paths (to be recorded as `skipped_persistent_workspaces` only).

Sources always included when they exist:

- `%USERPROFILE%\.cursor`, `%APPDATA%\Cursor` (Cursor state and chats)
- `%APPDATA%\Code` (VS Code state)
- `%APPDATA%\Python`, `%APPDATA%\pip`, `%APPDATA%\uv`
- `%LOCALAPPDATA%\miniconda3`, `miniforge3`, `mambaforge`, `anaconda3` (conda installs and envs)
- `%LOCALAPPDATA%\uv`, `%LOCALAPPDATA%\pip`, `%LOCALAPPDATA%\Programs`
- `%USERPROFILE%\Downloads`, `Documents`, `Desktop`, `Pictures`, `Videos`
- `%USERPROFILE%\.gitconfig`, `.ssh`, `.aws`, `.azure`, `.kube` when present

Excluded by default:

- `C:\Python311` and other system Pythons (the new workstation reprovisions these).
- `%LOCALAPPDATA%\Temp`, `%LOCALAPPDATA%\Cursor` (app cache).
- Browser cache dirs under `%LOCALAPPDATA%\Microsoft\Edge\User Data`, `Google\Chrome\User Data`, `Mozilla`.
- `node_modules` and `__pycache__` (robocopy `/XD`).
- Pass `-SkipVenv` to also exclude `.venv` and `.cache`.

Output:

- `H:\WorkStationXfer\migrations\YYYY-MM-DD_HHmmss\data\C\...` (exact-path mirror under `data\C\`).
- `migration-manifest.json` with item list, exit codes, discovered workspaces, and skipped items.
- `robocopy.log` with the full robocopy log.
- `RESTORE.md` copied from `H:\WorkStationXfer\RESTORE_PROMPT.md` so the snapshot is self-describing.

## Optional Flags

Pass these to the script when the user asks for non-default behavior:

```powershell
# Include extra paths the user mentions:
& Invoke-PrepareMigration.ps1 -ExtraIncludePaths @('C:\custom\project','D:\workspace')

# Skip venv and cache directories to keep snapshot small:
& Invoke-PrepareMigration.ps1 -SkipVenv

# Plan-only (no copy):
& Invoke-PrepareMigration.ps1 -DryRun
```

## Safety

- Never call `robocopy /MIR`. Always `/E /COPY:DAT`.
- Never delete or move anything from source paths.
- Never copy anything off `H:` or `N:`. Those drives are preserved by definition.
- If `H:\WorkStationXfer` does not exist, stop and report.

## Verification

After the script finishes, run this and read it back to the user:

```powershell
$root = "<snapshot_root from script output>"
Test-Path "$root\migration-manifest.json"
$manifest = Get-Content -Raw "$root\migration-manifest.json" | ConvertFrom-Json
$liveJsonl = (Get-ChildItem "$env:USERPROFILE\.cursor\projects" -Recurse -Filter *.jsonl -ErrorAction SilentlyContinue | Where-Object { $_.FullName -match "agent-transcripts\\[^\\]+\\[^\\]+\.jsonl$" }).Count
$snapJsonl = (Get-ChildItem "$root\data\C\Users\$($manifest.source.user_name)\.cursor\projects" -Recurse -Filter *.jsonl -ErrorAction SilentlyContinue | Where-Object { $_.FullName -match "agent-transcripts\\[^\\]+\\[^\\]+\.jsonl$" }).Count
"$liveJsonl live transcripts, $snapJsonl in snapshot"
```

The snapshot transcript count should be >= live minus 1 (the active chat may be locked).

## Companion Skill File

There is a mirrored copy of this skill at `H:\WorkStationXfer\skills\PrepareMigration\` so the skill source survives the wipe. The restore prompt at `H:\WorkStationXfer\RESTORE_PROMPT.md` runs `H:\WorkStationXfer\skills\PrepareMigration\scripts\Invoke-RestoreMigration.ps1` on the new machine.
