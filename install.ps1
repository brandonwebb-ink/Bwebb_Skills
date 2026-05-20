[CmdletBinding()]
param(
    # Names of skill folders to install. Default: all skills found in the repo.
    [string[]]$Skills = @(),

    # Where Cursor looks for personal skills. Override only for testing.
    [string]$Destination = "$env:USERPROFILE\.cursor\skills",

    # Show what would be installed without copying.
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'

function Write-Section($msg) { Write-Host ""; Write-Host "==== $msg ====" }

# Resolve repo root. $PSScriptRoot is set when the script is run via -File.
# Fall back to MyInvocation if dot-sourced.
$repoRoot = $PSScriptRoot
if (-not $repoRoot) { $repoRoot = Split-Path -Parent $MyInvocation.MyCommand.Path }
if (-not $repoRoot) { throw "Could not determine the repo root from `$PSScriptRoot. Run this script via -File." }

Write-Section "Bwebb_Skills installer"
Write-Host "Repo root:   $repoRoot"
Write-Host "Destination: $Destination"
if ($DryRun) { Write-Host "Mode:        DRY RUN (no files will be copied)" }

# Any folder containing a SKILL.md is treated as an installable skill.
$skillFolders = Get-ChildItem -LiteralPath $repoRoot -Directory | Where-Object {
    Test-Path -LiteralPath (Join-Path $_.FullName 'SKILL.md')
}

if (-not $skillFolders) {
    throw "No skill folders (with a SKILL.md) found under $repoRoot."
}

if ($Skills.Count -gt 0) {
    $known   = $skillFolders.Name
    $missing = $Skills | Where-Object { $_ -notin $known }
    foreach ($m in $missing) { Write-Warning "Skill not found in repo: $m" }
    $toInstall = $skillFolders | Where-Object { $_.Name -in $Skills }
    if (-not $toInstall) { throw "None of the requested skills exist in this repo. Found: $($known -join ', ')" }
} else {
    $toInstall = $skillFolders
}

Write-Section "Installing $($toInstall.Count) skill(s)"
$toInstall | ForEach-Object { Write-Host " - $($_.Name)" }

if (-not $DryRun) {
    New-Item -ItemType Directory -Force -Path $Destination | Out-Null
}

$results = New-Object System.Collections.Generic.List[psobject]
foreach ($s in $toInstall) {
    $src = $s.FullName
    $dst = Join-Path $Destination $s.Name

    Write-Host ""
    Write-Host "[$($s.Name)]"
    Write-Host "  $src"
    Write-Host "  -> $dst"

    if ($DryRun) {
        $results.Add([pscustomobject]@{ name=$s.Name; src=$src; dst=$dst; exit_code=-1 })
        continue
    }

    # /E recurse, /COPY:DAT data+attrs+timestamps, /XJ skip junctions,
    # /R:2 /W:2 brief retries, /NFL /NDL /NP quieter output.
    # Deliberately no /MIR or /MOVE — we never want to remove existing files
    # at the destination or remove anything from the source.
    & robocopy.exe $src $dst /E /COPY:DAT /XJ /R:2 /W:2 /NFL /NDL /NP | Out-Null
    $code = $LASTEXITCODE
    $results.Add([pscustomobject]@{ name=$s.Name; src=$src; dst=$dst; exit_code=$code })
    if ($code -ge 8) {
        Write-Warning "robocopy returned $code for $($s.Name); see https://learn.microsoft.com/windows-server/administration/windows-commands/robocopy#exit-return-codes"
    }
}

Write-Section "Summary"
$bad = @($results | Where-Object { $_.exit_code -ge 8 })
if ($DryRun) {
    Write-Host "DRY RUN COMPLETE. Re-run without -DryRun to install."
} elseif ($bad.Count -gt 0) {
    Write-Host "INSTALL FINISHED WITH WARNINGS"
    $bad | ForEach-Object { Write-Host (" - {0} exit={1}" -f $_.name, $_.exit_code) }
} else {
    Write-Host "INSTALL OK"
}

Write-Host ""
Write-Host "Installed skills:"
$results | ForEach-Object { Write-Host (" - {0,-24} {1}" -f $_.name, $_.dst) }
Write-Host ""
Write-Host "Restart Cursor or open a fresh chat to discover the skills."

if ($bad.Count -gt 0) { exit 8 } else { exit 0 }
