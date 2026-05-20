[CmdletBinding()]
param(
    [string]$MigrationRoot = 'H:\WorkStationXfer\migrations',
    [string]$SnapshotPath,
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'

function Write-Section($msg) { Write-Host ""; Write-Host "==== $msg ====" }

# ---------- 1. Find snapshot ----------
if (-not (Test-Path -LiteralPath $MigrationRoot)) {
    throw "Migration root not found: $MigrationRoot. Map H: drive first or pass -MigrationRoot."
}

if (-not $SnapshotPath) {
    $candidates = Get-ChildItem -LiteralPath $MigrationRoot -Directory `
        | Where-Object { Test-Path (Join-Path $_.FullName 'migration-manifest.json') } `
        | Sort-Object Name -Descending
    $latest = $null
    foreach ($cand in $candidates) {
        try {
            $m = Get-Content -Raw -LiteralPath (Join-Path $cand.FullName 'migration-manifest.json') | ConvertFrom-Json
            if ($m.PSObject.Properties.Match('dry_run').Count -gt 0 -and $m.dry_run) {
                Write-Host "Skipping dry-run snapshot: $($cand.FullName)"
                continue
            }
            $latest = $cand
            break
        } catch {
            Write-Warning "Could not parse manifest in $($cand.FullName); skipping."
        }
    }
    if (-not $latest) {
        throw "No non-dry-run snapshot with a parseable migration-manifest.json found under $MigrationRoot"
    }
    $SnapshotPath = $latest.FullName
}

$manifestPath = Join-Path $SnapshotPath 'migration-manifest.json'
if (-not (Test-Path -LiteralPath $manifestPath)) {
    throw "Manifest missing at $manifestPath. Did the snapshot finish?"
}

Write-Host "Using snapshot: $SnapshotPath"
$manifest = Get-Content -Raw -LiteralPath $manifestPath | ConvertFrom-Json

# ---------- 2. Username remap check ----------
$newUser = $env:USERNAME
$oldUser = $manifest.source.user_name
if ($newUser -and $oldUser -and ($newUser -ne $oldUser)) {
    Write-Host ""
    Write-Host "USERNAME REMAP NOTICE"
    Write-Host "  source user: $oldUser"
    Write-Host "  current user: $newUser"
    Write-Host "  Files under data\C\Users\$oldUser\... will be restored to %USERPROFILE% ($env:USERPROFILE)."
}

# ---------- 3. Restore each item ----------
$restoreLog = Join-Path $SnapshotPath 'restore.log'
$rcArgs = @('/E','/COPY:DAT','/DCOPY:DAT','/XJ','/R:2','/W:2','/MT:16','/NP','/NDL','/NS','/NC','/TEE',"/LOG+:$restoreLog")

$results = New-Object System.Collections.Generic.List[psobject]

Write-Section "Restoring $($manifest.items.Count) items"
foreach ($it in $manifest.items) {
    $tpl = $it.restore_target_template
    if (-not $tpl) {
        Write-Warning "Item has no restore_target_template, skipping: $($it.source_path)"
        continue
    }
    $target = $tpl
    $target = $target.Replace('%USERPROFILE%',   $env:USERPROFILE)
    $target = $target.Replace('%APPDATA%',       $env:APPDATA)
    $target = $target.Replace('%LOCALAPPDATA%',  $env:LOCALAPPDATA)

    $src = Join-Path $SnapshotPath $it.snapshot_rel
    if (-not (Test-Path -LiteralPath $src)) {
        Write-Host "Skipping (snapshot data missing): $src"
        continue
    }

    Write-Host ""
    Write-Host "[$($it.category)] $($it.source_path)"
    Write-Host "  -> $target"

    if ($DryRun) {
        $results.Add([pscustomobject]@{
            source     = $it.source_path
            target     = $target
            category   = $it.category
            exit_code  = -1
        })
        continue
    }

    $itemType = if ($it.PSObject.Properties.Match('type').Count -gt 0) { $it.type } else { $null }
    if (-not $itemType) {
        $itemType = if (Test-Path -LiteralPath $src -PathType Leaf) { 'file' } else { 'dir' }
    }

    if ($itemType -eq 'file') {
        $targetDir = Split-Path -Parent $target
        New-Item -ItemType Directory -Force -Path $targetDir | Out-Null
        try {
            Copy-Item -LiteralPath $src -Destination $target -Force
            $exit = 0
        } catch {
            Write-Warning "Copy-Item failed: $($_.Exception.Message)"
            $exit = 16
        }
    } else {
        New-Item -ItemType Directory -Force -Path $target | Out-Null
        & robocopy.exe $src $target @rcArgs | Out-Null
        $exit = $LASTEXITCODE
    }

    $results.Add([pscustomobject]@{
        source     = $it.source_path
        target     = $target
        category   = $it.category
        exit_code  = $exit
    })
    Write-Host ("  exit={0}" -f $exit)
}

# ---------- 4. Summary ----------
Write-Section "Summary"
$bad = @($results | Where-Object { $_.exit_code -ge 8 })
$partial = @($bad | Where-Object { $_.exit_code -lt 16 })
$fatal = @($bad | Where-Object { $_.exit_code -ge 16 })

Write-Host "RESTORE_COMPLETE"
Write-Host "Snapshot used: $SnapshotPath"
Write-Host "Items restored: $($results.Count)"
Write-Host "Partial (exit 8-15): $($partial.Count)"
Write-Host "Fatal (exit >=16): $($fatal.Count)"
if ($partial.Count -gt 0) {
    Write-Host "Partial items:"
    $partial | ForEach-Object { Write-Host (" - {0} -> {1} exit={2}" -f $_.source, $_.target, $_.exit_code) }
}
if ($fatal.Count -gt 0) {
    Write-Host "FATAL items:"
    $fatal | ForEach-Object { Write-Host (" - {0} -> {1} exit={2}" -f $_.source, $_.target, $_.exit_code) }
}

Write-Host ""
Write-Host "Next steps:"
Write-Host " 1. Make sure H: and N: drives are mapped to the same letters as before."
Write-Host " 2. Launch Cursor; chats and projects should appear under recent workspaces."
Write-Host " 3. If a workspace does not auto-open, use File > Open Folder with the original path."

if ($fatal.Count -gt 0) { exit 16 } else { exit 0 }
