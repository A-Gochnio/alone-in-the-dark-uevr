<#
.SYNOPSIS
Restores Arek's own Alone in the Dark saves (and optionally his audio volume) from a backup made by a test session.

.DESCRIPTION
Puzzle-testing sessions back up %LOCALAPPDATA%\AloneInTheDark\Saved\SaveGames to
backups\saves-before-puzzle-tests-<timestamp>\ (with SHA256SUMS.txt and GameUserSettings.ini).
This script stops if the game is running, keeps a copy of the current save folder (test saves) in
backups\saves-replaced-<timestamp>\, copies the backed-up save_*.sav, profile.sav and
steam_autocloud.vdf back, removes save slots that were not in the backup, and verifies the hashes.
settings.sav and GameUserSettings.ini are only restored with -RestoreSettings, which also brings the
original volume back (tests run with volume 0). Steam Cloud syncs the restored files on the next launch.

.EXAMPLE
./tools/Restore-AitDSaves.ps1                     # latest backup, saves only (volume stays 0)
./tools/Restore-AitDSaves.ps1 -RestoreSettings    # saves and settings, including volume
#>
param(
    [string]$BackupDirectory,
    [switch]$RestoreSettings
)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$saved = Join-Path $env:LOCALAPPDATA 'AloneInTheDark\Saved'
$saveGames = Join-Path $saved 'SaveGames'
$userSettings = Join-Path $saved 'Config\WindowsNoEditor\GameUserSettings.ini'

if (Get-Process AloneInTheDark-Win64-Shipping -ErrorAction SilentlyContinue) { throw 'Close the game first.' }
if (!$BackupDirectory) {
    $BackupDirectory = (Get-ChildItem (Join-Path $root 'backups') -Directory -Filter 'saves-before-puzzle-tests-*' |
        Sort-Object Name | Select-Object -Last 1).FullName
}
if (!$BackupDirectory -or !(Test-Path (Join-Path $BackupDirectory 'SHA256SUMS.txt'))) { throw "No backup with SHA256SUMS.txt found." }
Write-Host "Restoring from $BackupDirectory"

$keep = Join-Path $root "backups\saves-replaced-$(Get-Date -Format yyyyMMdd-HHmmss)"
Copy-Item $saveGames $keep -Recurse
Write-Host "Current saves kept in $keep"

$sums = @{}
foreach ($line in Get-Content (Join-Path $BackupDirectory 'SHA256SUMS.txt')) {
    $hash, $name = $line -split '  ', 2
    $sums[$name] = $hash
}
$saveFiles = $sums.Keys | Where-Object { $_ -match '^(save_\d+|profile)\.sav$|^steam_autocloud\.vdf$' }
Get-ChildItem $saveGames -Filter 'save_*.sav' | Where-Object { $saveFiles -notcontains $_.Name } | ForEach-Object {
    Remove-Item $_.FullName
    Write-Host "Removed test slot $($_.Name)"
}
foreach ($name in $saveFiles) { Copy-Item (Join-Path $BackupDirectory $name) (Join-Path $saveGames $name) -Force }
if ($RestoreSettings) {
    Copy-Item (Join-Path $BackupDirectory 'settings.sav') (Join-Path $saveGames 'settings.sav') -Force
    Copy-Item (Join-Path $BackupDirectory 'GameUserSettings.ini') $userSettings -Force
    $saveFiles += 'settings.sav'
}

$bad = @()
foreach ($name in $saveFiles) {
    if ((Get-FileHash (Join-Path $saveGames $name) -Algorithm SHA256).Hash -ne $sums[$name]) { $bad += $name }
}
if ($bad) { throw "Hash mismatch after restore: $($bad -join ', ')" }
Write-Host "Restored and verified: $($saveFiles -join ', ')"
