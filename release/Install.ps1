[CmdletBinding()]
param(
    # Leave Engine.ini alone (install only the UEVR profile).
    [switch]$SkipEngineIni,
    # Move the profile out of UEVR's folder and remove the Engine.ini lines again.
    [switch]$Uninstall,
    # Run even while the game is running (changes apply on its next start).
    [switch]$Force
)

# Alone in the Dark (2024) VR installer. Run it from the extracted release folder (Install.bat does).
# - Installs the UEVR profile to %APPDATA%\UnrealVRMod\AloneInTheDark-Win64-Shipping. An existing
#   profile is moved to a "-backup-<time>" folder next to it first, so old scripts can't interfere.
# - Adds the recommended CVars to the game's Engine.ini between "; AitD VR" marker lines, after
#   backing the file up. Rerunning replaces that block; nothing outside it is changed.
# Nothing is ever deleted: uninstalling moves the profile to a backup folder as well.

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.IO.Compression.FileSystem

$here = $PSScriptRoot
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$uevrRoot = Join-Path $env:APPDATA 'UnrealVRMod'
$profileDir = Join-Path $uevrRoot 'AloneInTheDark-Win64-Shipping'
$profileZip = Join-Path $here 'AloneInTheDark-Win64-Shipping.zip'
$cvarFile = Join-Path $here 'Engine-ini-additions.txt'
$engineIni = Join-Path $env:LOCALAPPDATA 'AloneInTheDark\Saved\Config\WindowsNoEditor\Engine.ini'
$beginMarker = '; AitD VR begin (added by the VR mod installer; rerun Install.bat -Uninstall to remove)'
$endMarker = '; AitD VR end'

function Write-Step([string]$Text) { Write-Host "-> $Text" -ForegroundColor Cyan }

if (!$Force -and (Get-Process -Name 'AloneInTheDark-Win64-Shipping' -ErrorAction SilentlyContinue)) {
    throw 'Alone in the Dark is running. Quit the game first, then run the installer again.'
}

function Move-ExistingProfile {
    if (!(Test-Path -LiteralPath $profileDir)) { return }
    $backup = "$profileDir-backup-$stamp"
    Move-Item -LiteralPath $profileDir -Destination $backup
    Write-Step "Moved the existing UEVR profile to $backup"
}

# Removes our marked block from Engine.ini lines.
function Remove-CVarBlock([string[]]$Lines) {
    $out = New-Object System.Collections.Generic.List[string]
    $inside = $false
    foreach ($line in $Lines) {
        if ($line -eq $beginMarker -or $line -like '; AitD VR begin*') { $inside = $true; continue }
        if ($inside) { if ($line -eq $endMarker) { $inside = $false }; continue }
        $out.Add($line)
    }
    return $out.ToArray()
}

function Backup-EngineIni {
    if (!(Test-Path -LiteralPath $engineIni)) { return }
    $backup = "$engineIni.backup-$stamp"
    Copy-Item -LiteralPath $engineIni -Destination $backup
    Write-Step "Backed up Engine.ini to $backup"
}

if ($Uninstall) {
    Move-ExistingProfile
    if (Test-Path -LiteralPath $engineIni) {
        $lines = [IO.File]::ReadAllLines($engineIni)
        if ($lines -contains $endMarker) {
            Backup-EngineIni
            [IO.File]::WriteAllLines($engineIni, [string[]]@(Remove-CVarBlock $lines))
            Write-Step 'Removed the VR lines from Engine.ini'
        }
    }
    Write-Host ''
    Write-Host 'Uninstalled. Your older profile backups (if any) are the "-backup-" folders in' -ForegroundColor Green
    Write-Host "$uevrRoot"
    return
}

foreach ($f in @($profileZip, $cvarFile)) {
    if (!(Test-Path -LiteralPath $f)) { throw "Missing $f. Extract the whole release zip first, then run Install.bat from that folder." }
}

# 1. UEVR profile.
Move-ExistingProfile
New-Item -ItemType Directory -Force -Path $profileDir | Out-Null
[IO.Compression.ZipFile]::ExtractToDirectory($profileZip, $profileDir)
Write-Step "Installed the UEVR profile to $profileDir"

# 2. Engine.ini.
if ($SkipEngineIni) {
    Write-Step 'Skipped Engine.ini (-SkipEngineIni)'
} else {
    $cvars = @([IO.File]::ReadAllLines($cvarFile) | Where-Object { $_ -match '^[^\[;].*=' })
    $keys = @($cvars | ForEach-Object { ($_ -split '=', 2)[0].Trim() })
    $lines = @()
    if (Test-Path -LiteralPath $engineIni) {
        Backup-EngineIni
        $lines = [string[]]@(Remove-CVarBlock ([IO.File]::ReadAllLines($engineIni)))
    } else {
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $engineIni) | Out-Null
    }
    $block = @($beginMarker) + $cvars + @($endMarker)

    # Put the block at the top of an existing [SystemSettings] section and drop the same keys from
    # that section, so the game sees each value once. Otherwise add the section at the end.
    $out = New-Object System.Collections.Generic.List[string]
    $section = $null
    $placed = $false
    foreach ($line in $lines) {
        if ($line -match '^\s*\[(.+)\]\s*$') {
            $section = $Matches[1]
            $out.Add($line)
            if ($section -eq 'SystemSettings' -and !$placed) { $block | ForEach-Object { $out.Add($_) }; $placed = $true }
            continue
        }
        if ($section -eq 'SystemSettings' -and $line -match '^\s*([^=;]+?)\s*=' -and $keys -contains $Matches[1]) {
            Write-Step "Replaced your own Engine.ini line: $line"
            continue
        }
        $out.Add($line)
    }
    if (!$placed) {
        if ($out.Count -gt 0 -and $out[$out.Count - 1].Trim() -ne '') { $out.Add('') }
        $out.Add('[SystemSettings]')
        $block | ForEach-Object { $out.Add($_) }
    }
    [IO.File]::WriteAllLines($engineIni, $out.ToArray())
    Write-Step "Added $($cvars.Count) VR settings to $engineIni"
}

Write-Host ''
Write-Host 'Installed. Next:' -ForegroundColor Green
Write-Host '  1. Set the in-game graphics options from README.txt (DLSS Quality, shadows Low, ...).'
Write-Host '  2. Start the game, then UEVR nightly 01143: select AloneInTheDark-Win64-Shipping, OpenXR, Inject.'
Write-Host '  3. If the UEVR menu is open after injecting, close it (Insert, or hold both thumbsticks).'
Write-Host 'To undo: Install.bat -Uninstall'
