<#
.SYNOPSIS
Repeatedly reloads the newest save from the pause menu and records whether the game survives.

.DESCRIPTION
Each attempt: wait for gameplay (main state 0 in data/aitd_ui_state.txt, written by
aitd_vr_ui.lua), draw a weapon with -DrawKey ('' to skip), stay in gameplay for -GameplaySeconds, then Escape > Load game > newest slot.
After a crash it copies UEVR's log.txt (overwritten on the next injection) and the newest UE
crash folder into -OutDir. Keys are posted to the game window (no focus needed).

.EXAMPLE
./tools/Test-AitDReloadLoop.ps1 -Count 8 -OutDir local/crash-analysis-20261026/repro/baseline
#>
param(
    [int]$Count = 8,
    [int]$GameplaySeconds = 20,
    [int]$LoadTimeoutSeconds = 120,
    [string]$DrawKey = 'D1',
    [string]$OutDir = "local/crash-analysis-20261026/repro/run-$(Get-Date -Format yyyyMMdd-HHmmss)"
)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root
New-Item -ItemType Directory -Force $OutDir | Out-Null
$profileDir = Join-Path $env:APPDATA 'UnrealVRMod\AloneInTheDark-Win64-Shipping'
$stateFile = Join-Path $profileDir 'data\aitd_ui_state.txt'
$crashes = Join-Path $env:LOCALAPPDATA 'AloneInTheDark\Saved\Crashes'
$log = Join-Path $OutDir 'results.txt'
$shot = Join-Path $PSScriptRoot 'Get-AitDWindowShot.ps1'

function Write-Result($text) {
    $line = "$(Get-Date -Format 'HH:mm:ss') $text"
    Add-Content $log $line
    $line
}

function Get-MainState {
    try { if ((Get-Content $stateFile -Raw) -match 'state=(\S+)') { return $Matches[1] } } catch {}
    return $null
}

function Test-Alive { [bool](Get-Process AloneInTheDark-Win64-Shipping -ErrorAction SilentlyContinue) }

function Save-CrashEvidence($tag) {
    $dest = Join-Path $OutDir $tag
    New-Item -ItemType Directory -Force $dest | Out-Null
    Copy-Item (Join-Path $profileDir 'log.txt') (Join-Path $dest 'uevr-log.txt') -ErrorAction SilentlyContinue
    Copy-Item (Join-Path $profileDir 'data\aitd_*.txt') $dest -ErrorAction SilentlyContinue
    $newest = Get-ChildItem $crashes -Directory -ErrorAction SilentlyContinue | Sort-Object LastWriteTime | Select-Object -Last 1
    if ($newest -and $newest.LastWriteTime -gt $script:started) {
        Copy-Item $newest.FullName (Join-Path $dest $newest.Name) -Recurse
    }
}

$script:started = Get-Date
Write-Result "start: $Count reloads, $GameplaySeconds s in gameplay each"
for ($i = 1; $i -le $Count; $i++) {
    # Wait for gameplay.
    $deadline = (Get-Date).AddSeconds($LoadTimeoutSeconds)
    while ((Get-MainState) -ne '0' -and (Get-Date) -lt $deadline -and (Test-Alive)) { Start-Sleep 1 }
    if (!(Test-Alive)) { Write-Result "attempt ${i}: CRASH while loading"; Save-CrashEvidence "crash-$i"; break }
    if ((Get-MainState) -ne '0') { Write-Result "attempt ${i}: no gameplay state after $LoadTimeoutSeconds s (state=$(Get-MainState))"; break }
    $inGame = Get-Date
    if ($DrawKey) {
        # Draw a weapon so the weapon attachment runs on every new pawn.
        Start-Sleep 3
        & $shot -Keys $DrawKey -DelayMs 200 -Out (Join-Path $OutDir "draw-$i.png") | Out-Null
    }
    while (((Get-Date) - $inGame).TotalSeconds -lt $GameplaySeconds -and (Test-Alive)) { Start-Sleep 1 }
    if (!(Test-Alive)) {
        Write-Result ("attempt ${i}: CRASH {0:N0} s into gameplay" -f ((Get-Date) - $inGame).TotalSeconds)
        Save-CrashEvidence "crash-$i"
        break
    }
    Write-Result "attempt ${i}: ok ($GameplaySeconds s in gameplay), reloading"
    & $shot -Keys 'Escape', 'sleep1200', 'Down', 'Down', 'E', 'sleep1500', 'E' -DelayMs 1000 -Out (Join-Path $OutDir "reload-$i.png") | Out-Null
    Start-Sleep 5
}
if (Test-Alive) {
    $deadline = (Get-Date).AddSeconds($LoadTimeoutSeconds)
    while ((Get-MainState) -ne '0' -and (Get-Date) -lt $deadline -and (Test-Alive)) { Start-Sleep 1 }
    Start-Sleep $GameplaySeconds
    Write-Result ("end: game {0}, state={1}" -f $(if (Test-Alive) { 'alive' } else { 'CRASHED after last reload' }), (Get-MainState))
    if (!(Test-Alive)) { Save-CrashEvidence 'crash-final' }
}
