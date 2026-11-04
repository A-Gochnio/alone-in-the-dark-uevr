param([switch]$NoSave, [switch]$GiveWeapons)
# Restarts the game into VR (window moved to local\machine.psd1's WindowPosition, if set): deploys profile/scripts/*.lua to the UEVR profile,
# kills and relaunches with -dx12, injects UEVR, loads the save with E and closes the UEVR menu,
# which reopens after the load even though the injector already sent Insert. -GiveWeapons then runs
# Grant-AitDWeapons.ps1 (all firearms and ammo, for testing).
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root
. (Join-Path $PSScriptRoot 'AitDCommon.ps1')
$profileScripts = Join-Path $env:APPDATA 'UnrealVRMod\AloneInTheDark-Win64-Shipping\scripts'
$exe = Get-AitDGameExe
Get-ChildItem (Join-Path $root 'profile\scripts') -Filter 'aitd_vr*.lua' | Copy-Item -Destination $profileScripts
Copy-Item (Join-Path $root 'profile\scripts\alone_in_the_dark_vr.lua') $profileScripts
Get-Process AloneInTheDark-Win64-Shipping -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep 5
Start-Process $exe -ArgumentList '-dx12' -WorkingDirectory (Split-Path $exe)
$p = $null
for ($i = 0; $i -lt 60 -and !$p; $i++) { Start-Sleep 2; $p = Get-Process AloneInTheDark-Win64-Shipping -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowHandle -ne 0 } }
if (!$p) { throw 'Game window did not appear.' }
Move-AitDGameWindow $p.MainWindowHandle
& (Join-Path $PSScriptRoot 'Invoke-AitDUevrInject.ps1') | Out-Null
if ($NoSave) { return }
Start-Sleep 15
& (Join-Path $PSScriptRoot 'Get-AitDWindowShot.ps1') -Keys 'e' -Out 'local/ui-captures/restart-load.png' | Out-Null
Start-Sleep 45
& (Join-Path $PSScriptRoot 'Get-AitDWindowShot.ps1') -Keys 'Insert' -Out 'local/ui-captures/restart-ingame.png' | Out-Null
# The menu's state after the load varies, so check the capture for its grey title bar (73,73,73 at
# y=380 in the 2560x1440 window) and toggle again if it is open.
Add-Type -AssemblyName System.Drawing
function Test-UevrMenu {
    & (Join-Path $PSScriptRoot 'Get-AitDWindowShot.ps1') -Out 'local/ui-captures/restart-check.png' | Out-Null
    $bmp = [Drawing.Bitmap]::FromFile((Join-Path $root 'local\ui-captures\restart-check.png'))
    try { @(1200, 1300, 1400, 1500 | Where-Object { $p = $bmp.GetPixel($_, 380); $p.R -eq 73 -and $p.G -eq 73 -and $p.B -eq 73 }).Count -eq 4 }
    finally { $bmp.Dispose() }
}
for ($i = 0; $i -lt 3; $i++) {
    Start-Sleep 3
    if (!(Test-UevrMenu)) { break }
    & (Join-Path $PSScriptRoot 'Get-AitDWindowShot.ps1') -Keys 'Insert' -Out 'local/ui-captures/restart-ingame.png' | Out-Null
}
if ($GiveWeapons) { & (Join-Path $PSScriptRoot 'Grant-AitDWeapons.ps1') }
'Loaded; check local/ui-captures/restart-ingame.png for a closed UEVR menu.'
