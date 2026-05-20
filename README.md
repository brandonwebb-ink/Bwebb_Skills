# Bwebb_Skills

Personal Cursor Agent Skills by `bwebb`. Each subfolder is a self-contained
skill ready to drop into `%USERPROFILE%\.cursor\skills\` on a Windows machine.

## Skills

- [PrepareMigration](PrepareMigration/) — Snapshot Cursor state, user data,
  and C-drive project roots to a timestamped folder, and restore the latest
  snapshot to a fresh workstation. Windows + PowerShell + robocopy.

## Install a single skill

```powershell
git clone https://github.com/<owner>/Bwebb_Skills "$env:USERPROFILE\Bwebb_Skills"
robocopy "$env:USERPROFILE\Bwebb_Skills\<SkillName>" `
         "$env:USERPROFILE\.cursor\skills\<SkillName>" `
         /E /COPY:DAT /R:2 /W:2
```

Restart Cursor or open a fresh chat and the skill is discoverable.

## License

MIT. See [LICENSE](LICENSE).
