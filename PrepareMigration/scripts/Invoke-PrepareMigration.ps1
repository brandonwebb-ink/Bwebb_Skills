[CmdletBinding()]
param(
    [string]$MigrationRoot      = 'H:\WorkStationXfer\migrations',
    [string]$RestorePromptPath  = 'H:\WorkStationXfer\RESTORE_PROMPT.md',
    [string[]]$ExtraIncludePaths = @(),
    [switch]$SkipVenv,
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'

function Write-Section($msg) { Write-Host ""; Write-Host "==== $msg ====" }

# ---------- 0. Sanity ----------
$migrationRootParent = Split-Path -Parent $MigrationRoot
if (-not (Test-Path -LiteralPath $migrationRootParent)) {
    throw "Migration parent path missing: $migrationRootParent. Map H: drive or pass -MigrationRoot."
}
New-Item -ItemType Directory -Force -Path $MigrationRoot | Out-Null

# ---------- 1. Environment ----------
$userProfile  = $env:USERPROFILE
$appData      = $env:APPDATA
$localAppData = $env:LOCALAPPDATA
$userName     = $env:USERNAME
$machineName  = $env:COMPUTERNAME

# ---------- 2. Timestamped snapshot folder ----------
$ts            = (Get-Date).ToString('yyyy-MM-dd_HHmmss')
$snapshotRoot  = Join-Path $MigrationRoot $ts
$dataRoot      = Join-Path $snapshotRoot 'data'
$manifestPath  = Join-Path $snapshotRoot 'migration-manifest.json'
$robocopyLog   = Join-Path $snapshotRoot 'robocopy.log'
New-Item -ItemType Directory -Force -Path $snapshotRoot | Out-Null
New-Item -ItemType Directory -Force -Path $dataRoot     | Out-Null

Write-Host "Snapshot root: $snapshotRoot"

# ---------- 3. Core sources (directories + files) ----------
$coreDirs = @(
    @{ src="$userProfile\.cursor";          cat='cursor-state'; tpl='%USERPROFILE%\.cursor' }
    @{ src="$appData\Cursor";               cat='cursor-state'; tpl='%APPDATA%\Cursor' }
    @{ src="$appData\Code";                 cat='editor-state'; tpl='%APPDATA%\Code' }
    @{ src="$appData\Python";               cat='user-runtime'; tpl='%APPDATA%\Python' }
    @{ src="$appData\pip";                  cat='user-runtime'; tpl='%APPDATA%\pip' }
    @{ src="$appData\uv";                   cat='user-runtime'; tpl='%APPDATA%\uv' }
    @{ src="$localAppData\miniconda3";      cat='user-runtime'; tpl='%LOCALAPPDATA%\miniconda3' }
    @{ src="$localAppData\miniforge3";      cat='user-runtime'; tpl='%LOCALAPPDATA%\miniforge3' }
    @{ src="$localAppData\mambaforge";      cat='user-runtime'; tpl='%LOCALAPPDATA%\mambaforge' }
    @{ src="$localAppData\anaconda3";       cat='user-runtime'; tpl='%LOCALAPPDATA%\anaconda3' }
    @{ src="$localAppData\uv";              cat='user-runtime'; tpl='%LOCALAPPDATA%\uv' }
    @{ src="$localAppData\pip";             cat='user-runtime'; tpl='%LOCALAPPDATA%\pip' }
    @{ src="$localAppData\Programs";        cat='user-program'; tpl='%LOCALAPPDATA%\Programs' }
    @{ src="$userProfile\Downloads";        cat='user-data';    tpl='%USERPROFILE%\Downloads' }
    @{ src="$userProfile\Documents";        cat='user-data';    tpl='%USERPROFILE%\Documents' }
    @{ src="$userProfile\Desktop";          cat='user-data';    tpl='%USERPROFILE%\Desktop' }
    @{ src="$userProfile\Pictures";         cat='user-data';    tpl='%USERPROFILE%\Pictures' }
    @{ src="$userProfile\Videos";           cat='user-data';    tpl='%USERPROFILE%\Videos' }
    @{ src="$userProfile\.ssh";             cat='user-config';  tpl='%USERPROFILE%\.ssh' }
    @{ src="$userProfile\.aws";             cat='user-config';  tpl='%USERPROFILE%\.aws' }
    @{ src="$userProfile\.azure";           cat='user-config';  tpl='%USERPROFILE%\.azure' }
    @{ src="$userProfile\.kube";            cat='user-config';  tpl='%USERPROFILE%\.kube' }
)

$coreFiles = @(
    @{ src="$userProfile\.gitconfig";       cat='user-config';  tpl='%USERPROFILE%\.gitconfig' }
    @{ src="$userProfile\.npmrc";           cat='user-config';  tpl='%USERPROFILE%\.npmrc' }
    @{ src="$userProfile\.condarc";         cat='user-config';  tpl='%USERPROFILE%\.condarc' }
)

# ---------- 4. Discover Cursor workspaces ----------
Write-Section "Discovering Cursor workspaces"

function ConvertFrom-FileUri([string]$uri) {
    if (-not $uri) { return $null }
    if ($uri -notlike 'file:///*') { return $null }
    $p = $uri.Substring(8)
    $p = [System.Uri]::UnescapeDataString($p)
    $p = $p -replace '/','\'
    return $p
}

$workspaceFolders = New-Object System.Collections.Generic.HashSet[string]

$workspaceStorageDir = Join-Path $appData 'Cursor\User\workspaceStorage'
if (Test-Path -LiteralPath $workspaceStorageDir) {
    Get-ChildItem -LiteralPath $workspaceStorageDir -Filter workspace.json -Recurse -ErrorAction SilentlyContinue | ForEach-Object {
        try {
            $obj = Get-Content -Raw -LiteralPath $_.FullName | ConvertFrom-Json
            if ($obj.folder) { [void]$workspaceFolders.Add($obj.folder) }
        } catch {
            Write-Warning "Could not parse $($_.FullName): $($_.Exception.Message)"
        }
    }
}

$storageJsonPath = Join-Path $appData 'Cursor\User\globalStorage\storage.json'
if (Test-Path -LiteralPath $storageJsonPath) {
    try {
        $store = Get-Content -Raw -LiteralPath $storageJsonPath | ConvertFrom-Json
        if ($store.profileAssociations -and $store.profileAssociations.workspaces) {
            $store.profileAssociations.workspaces.PSObject.Properties | ForEach-Object { [void]$workspaceFolders.Add($_.Name) }
        }
    } catch {
        Write-Warning "Could not parse $storageJsonPath`: $($_.Exception.Message)"
    }
}

$cWorkspaces           = New-Object System.Collections.Generic.List[string]
$persistentWorkspaces  = New-Object System.Collections.Generic.List[string]

foreach ($uri in $workspaceFolders) {
    $local = ConvertFrom-FileUri $uri
    if (-not $local) { continue }
    if ($local -match '^[Cc]:\\') {
        [void]$cWorkspaces.Add($local)
    } else {
        [void]$persistentWorkspaces.Add($local)
    }
}

$systemExclude = @(
    'C:\Python311','C:\Python310','C:\Python312','C:\Python313','C:\Python39'
)
$cWorkspaces = $cWorkspaces | Sort-Object -Unique | Where-Object {
    $p = $_; -not ($systemExclude | Where-Object { $_ -ieq $p })
}
$persistentWorkspaces = $persistentWorkspaces | Sort-Object -Unique

Write-Host "Discovered C-drive workspaces: $($cWorkspaces.Count)"
Write-Host "Persistent (H:/N:/other) workspaces (recorded only): $($persistentWorkspaces.Count)"

# ---------- 5. Build full items list ----------
function Get-SnapshotRel([string]$src) {
    $drive = $src.Substring(0,1).ToUpper()
    $rest  = $src.Substring(3)  # skip "C:\"
    return "data\$drive\$rest"
}

$items = New-Object System.Collections.Generic.List[psobject]

foreach ($s in $coreDirs) {
    if (Test-Path -LiteralPath $s.src) {
        $items.Add([pscustomobject]@{
            category                = $s.cat
            type                    = 'dir'
            source_path             = $s.src
            snapshot_rel            = Get-SnapshotRel $s.src
            restore_target_template = $s.tpl
        })
    }
}

foreach ($s in $coreFiles) {
    if (Test-Path -LiteralPath $s.src -PathType Leaf) {
        $items.Add([pscustomobject]@{
            category                = $s.cat
            type                    = 'file'
            source_path             = $s.src
            snapshot_rel            = Get-SnapshotRel $s.src
            restore_target_template = $s.tpl
        })
    }
}

foreach ($w in $cWorkspaces) {
    if (Test-Path -LiteralPath $w) {
        # Skip if it's already covered by a core entry (e.g. .cursor)
        $alreadyCovered = $items | Where-Object { $_.source_path -ieq $w }
        if ($alreadyCovered) { continue }
        $items.Add([pscustomobject]@{
            category                = 'project'
            type                    = 'dir'
            source_path             = $w
            snapshot_rel            = Get-SnapshotRel $w
            restore_target_template = $w
        })
    }
}

foreach ($extra in $ExtraIncludePaths) {
    if (-not $extra) { continue }
    if (Test-Path -LiteralPath $extra) {
        $type = if ((Get-Item -LiteralPath $extra).PSIsContainer) { 'dir' } else { 'file' }
        $items.Add([pscustomobject]@{
            category                = 'extra'
            type                    = $type
            source_path             = $extra
            snapshot_rel            = Get-SnapshotRel $extra
            restore_target_template = $extra
        })
    } else {
        Write-Warning "Extra include path not found: $extra"
    }
}

Write-Section "Items to copy ($($items.Count))"
$items | ForEach-Object { Write-Host (" [{0}] {1}" -f $_.category, $_.source_path) }

# ---------- 6. Copy ----------
Write-Section "Copying"

$rcArgs = @('/E','/COPY:DAT','/DCOPY:DAT','/XJ','/R:2','/W:2','/MT:16','/NP','/NDL','/NS','/NC','/TEE',"/LOG+:$robocopyLog")
$excludeDirs = @('node_modules','__pycache__')
if ($SkipVenv) { $excludeDirs += @('.venv','.cache') }
$rcArgs += @('/XD') + $excludeDirs

foreach ($it in $items) {
    $dst = Join-Path $snapshotRoot $it.snapshot_rel
    Write-Host ""
    Write-Host "[$($it.category)] $($it.source_path)"
    Write-Host "  -> $dst"

    if ($DryRun) {
        Add-Member -InputObject $it -NotePropertyName robocopy_exit_code -NotePropertyValue -1 -Force
        continue
    }

    if ($it.type -eq 'file') {
        $dstDir = Split-Path -Parent $dst
        New-Item -ItemType Directory -Force -Path $dstDir | Out-Null
        try {
            Copy-Item -LiteralPath $it.source_path -Destination $dst -Force
            Add-Member -InputObject $it -NotePropertyName robocopy_exit_code -NotePropertyValue 0 -Force
        } catch {
            Write-Warning "Copy-Item failed for $($it.source_path): $($_.Exception.Message)"
            Add-Member -InputObject $it -NotePropertyName robocopy_exit_code -NotePropertyValue 16 -Force
        }
    } else {
        New-Item -ItemType Directory -Force -Path $dst | Out-Null
        & robocopy.exe $it.source_path $dst @rcArgs | Out-Null
        Add-Member -InputObject $it -NotePropertyName robocopy_exit_code -NotePropertyValue $LASTEXITCODE -Force
    }
}

# ---------- 7. Manifest ----------
Write-Section "Writing manifest"
$manifest = [pscustomobject]@{
    schema_version                = 1
    timestamp                     = $ts
    source                        = [pscustomobject]@{
        machine_name = $machineName
        user_name    = $userName
        user_profile = $userProfile
        app_data     = $appData
        local_app_data = $localAppData
    }
    snapshot_root                 = $snapshotRoot
    items                         = $items
    discovered_c_workspaces       = @($cWorkspaces)
    skipped_persistent_workspaces = @($persistentWorkspaces)
    skipped_system                = $systemExclude
    excluded_dirs                 = $excludeDirs
    skip_venv                     = [bool]$SkipVenv
    dry_run                       = [bool]$DryRun
}
$manifest | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $manifestPath -Encoding UTF8
Write-Host "Manifest: $manifestPath"

# ---------- 8. Copy restore prompt into snapshot ----------
if (Test-Path -LiteralPath $RestorePromptPath) {
    Copy-Item -LiteralPath $RestorePromptPath -Destination (Join-Path $snapshotRoot 'RESTORE.md') -Force
    Write-Host "RESTORE.md copied into snapshot"
} else {
    Write-Warning "RESTORE_PROMPT.md not found at $RestorePromptPath; snapshot will not be self-describing."
}

# ---------- 9. Summary ----------
Write-Section "Summary"
$bad = @($items | Where-Object { $_.robocopy_exit_code -ge 8 })
$partial = @($bad | Where-Object { $_.robocopy_exit_code -lt 16 })
$fatal = @($bad | Where-Object { $_.robocopy_exit_code -ge 16 })

Write-Host "MIGRATION_SNAPSHOT_READY: $snapshotRoot"
Write-Host "Items copied: $($items.Count)"
Write-Host "Partial (locked files, exit 8-15): $($partial.Count)"
Write-Host "Fatal (exit >=16): $($fatal.Count)"

if ($partial.Count -gt 0) {
    Write-Host "Partial items (likely locked files such as the active Cursor chat):"
    $partial | ForEach-Object { Write-Host (" - {0} exit={1}" -f $_.source_path, $_.robocopy_exit_code) }
}
if ($fatal.Count -gt 0) {
    Write-Host "FATAL items (no data copied, retry needed):"
    $fatal | ForEach-Object { Write-Host (" - {0} exit={1}" -f $_.source_path, $_.robocopy_exit_code) }
}

# Exit non-zero only for fatal failures; partial copies are usually fine for live snapshots
if ($fatal.Count -gt 0) { exit 16 } else { exit 0 }
