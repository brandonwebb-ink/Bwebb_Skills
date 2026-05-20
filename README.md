# Bwebb_Skills

Personal Cursor Agent Skills by `bwebb`. Each subfolder is a self-contained
skill ready to drop into `%USERPROFILE%\.cursor\skills\` on a Windows machine.

## Skills

- [PrepareMigration](PrepareMigration/) — Snapshot Cursor state, user data,
  and C-drive project roots to a timestamped folder, and restore the latest
  snapshot to a fresh workstation. Windows + PowerShell + robocopy.

## Quick install (recommended)

Clone the repo and run the installer. It copies every skill folder in this
repo into `%USERPROFILE%\.cursor\skills\<SkillName>\` using robocopy, with no
move/delete on the source.

```powershell
git clone https://github.com/<owner>/Bwebb_Skills "$env:USERPROFILE\Bwebb_Skills"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$env:USERPROFILE\Bwebb_Skills\install.ps1"
```

PowerShell 7 (`pwsh`) works too if it's on your PATH, but the installer is
written against Windows PowerShell 5.1 so it runs on a stock Windows machine
out of the box.

Restart Cursor or open a fresh chat and the skills are discoverable.

### Installer flags

| Flag | Purpose |
| --- | --- |
| `-Skills <name1>,<name2>` | Install only the named skill folders (default: all). |
| `-Destination <path>` | Override the install root. Default `%USERPROFILE%\.cursor\skills`. |
| `-DryRun` | Print what would be installed without copying. |

### Asking the agent to install

If you point an agent at this repo and say "install these skills," it should:

1. `git clone` the repo (or `cd` into an existing clone).
2. Run `install.ps1` from the repo root with `powershell.exe -NoProfile -ExecutionPolicy Bypass -File <abs path to install.ps1>`.
3. Restart Cursor.

That's it — no path discovery, no manual robocopy, no per-skill steps.

## Run a skill without installing

Each skill is self-contained under its own folder. You can invoke its scripts
directly from a clone without copying anything into `%USERPROFILE%\.cursor\skills\`.
The skill won't be auto-discovered by Cursor, but the underlying scripts work
the same way. Example:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File "$env:USERPROFILE\Bwebb_Skills\PrepareMigration\scripts\Invoke-PrepareMigration.ps1"
```

## Manual install (fallback)

If you'd rather not run the installer:

```powershell
robocopy "$env:USERPROFILE\Bwebb_Skills\<SkillName>" `
         "$env:USERPROFILE\.cursor\skills\<SkillName>" `
         /E /COPY:DAT /XJ /R:2 /W:2
```
