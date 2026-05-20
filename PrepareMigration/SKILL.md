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

Follow these steps in order. Do not improvise pre-checks; the script handles its own validation.

### 1. Tell the user to close all other Cursor windows

The Cursor window running this skill keeps running; robocopy retries handle the locked transcript file for the active chat.

### 2. Confirm `H:\WorkStationXfer` exists

```powershell
Test-Path 'H:\WorkStationXfer'
```

If this is `False`, stop and report. The script will not create the parent.

### 3. Locate `Invoke-PrepareMigration.ps1`

The script ships beside this `SKILL.md`. Resolve its absolute path using the FIRST option that succeeds:

1. **Use this SKILL.md's own folder.** You already have the absolute path to this file from your skill index. The script is at `<that folder>\scripts\Invoke-PrepareMigration.ps1`.
2. Else check, in order:
   - `$env:USERPROFILE\.cursor\skills\PrepareMigration\scripts\Invoke-PrepareMigration.ps1` (standard install)
   - `H:\WorkStationXfer\skills\PrepareMigration\scripts\Invoke-PrepareMigration.ps1` (mirrored copy on H:)
   - `$env:USERPROFILE\Bwebb_Skills\PrepareMigration\scripts\Invoke-PrepareMigration.ps1` (repo clone in user home)
   - Any path matching `*\Bwebb_Skills\PrepareMigration\scripts\Invoke-PrepareMigration.ps1` under the current workspace

If none of those exist, the skill isn't installed yet. Run the repo-root installer (`<repo>\install.ps1`) or copy `PrepareMigration\` into `%USERPROFILE%\.cursor\skills\` before continuing.

### 4. Invoke the script directly with `-File` and a literal path

Once you have the absolute path, run it like this — substitute the actual path for the placeholder:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File 'C:\absolute\path\to\Invoke-PrepareMigration.ps1'
```

`pwsh` (PowerShell 7) works equivalently if it's on PATH; the script is written against PowerShell 5.1 so `powershell.exe` is the safer default on a stock Windows machine.

**Do not** wrap this in any of the following antipatterns. Each one has bitten previous agent runs:

- `powershell -Command "$script = '...'; & $script"` — the outer shell can interpolate `$script` to empty before the inner shell sees it, and PowerShell reserves the `script:` scope qualifier. The script never runs.
- Building the path inside nested heredocs or interpolated strings across shells. Pass the path as ONE single-quoted literal after `-File`. Do not introduce a helper variable for the path.
- Do not use `Invoke-Expression` or `iex`. Always `-File '<absolute path>'`.

To pass optional flags (e.g. `-SkipVenv` or `-ExtraIncludePaths`), append them after `-File '<path>'`:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File 'C:\absolute\path\to\Invoke-PrepareMigration.ps1' -SkipVenv
```

### 5. Read back the result

The script prints `MIGRATION_SNAPSHOT_READY: <snapshot_path>` on success and lists any item with robocopy exit code >= 8. Report that summary verbatim to the user.

### 6. Handle failures explicitly

If any item failed (exit code >= 16), surface the failing source paths and ask the user whether to retry just those items or proceed. Exit codes 8-15 are usually locked-file partials and can typically be ignored; still mention them so the user can decide.

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
