<#
.SYNOPSIS
Sends simulated Quest controller input to the game through the virtual pad (tools/Start-AitDVirtualPad.ps1).

.DESCRIPTION
The virtual pad feeds these values into XInput, where alone_in_the_dark_vr.lua's remap runs on them
exactly as on the pad UEVR builds from the Quest controllers: RightGrip = RB, LeftGrip = LB, triggers =
LT/RT, A/B/X/Y, sticks, L3/R3 = stick clicks. Each call holds the given input for -Seconds, then
waits -Gap seconds of neutral input. Requires Start-AitDVirtualPad.ps1 running (ViGEmBus installed).

.EXAMPLE
./tools/Send-AitDSimQuest.ps1 -Press RightGrip,RightTrigger -Seconds 0.3
./tools/Send-AitDSimQuest.ps1 -LeftStick 0,-1 -Seconds 0.2
./tools/Send-AitDSimQuest.ps1 -Press LeftGrip -RightStick 0,1 -Seconds 0.3
#>
param(
    [ValidateSet('A', 'B', 'X', 'Y', 'LeftGrip', 'RightGrip', 'LeftTrigger', 'RightTrigger', 'L3', 'R3', 'Menu')]
    [string[]]$Press = @(),
    [double[]]$LeftStick = @(0, 0),
    [double[]]$RightStick = @(0, 0),
    [double]$Seconds = 0.15,
    [double]$Gap = 0.25,
    [int]$Repeat = 1
)
$ErrorActionPreference = 'Stop'
$data = Join-Path $env:APPDATA 'UnrealVRMod\AloneInTheDark-Win64-Shipping\data'
$file = Join-Path $data 'aitd_sim_input.txt'
$map = @{ A = 'A'; B = 'B'; X = 'X'; Y = 'Y'; LeftGrip = 'LB'; RightGrip = 'RB'; L3 = 'LS'; R3 = 'RS'; Menu = 'START' }
$buttons = ($Press | Where-Object { $map.ContainsKey($_) } | ForEach-Object { $map[$_] }) -join ','
$lt = if ($Press -contains 'LeftTrigger') { 255 } else { 0 }
$rt = if ($Press -contains 'RightTrigger') { 255 } else { 0 }
function Axis([double]$v) { [int][Math]::Round([Math]::Max(-1, [Math]::Min(1, $v)) * 32767) }
$inv = [Globalization.CultureInfo]::InvariantCulture
for ($i = 0; $i -lt $Repeat; $i++) {
    $seq = [DateTime]::UtcNow.Ticks / 10000 % 1000000000
    $line = "seq=$seq buttons=$buttons lt=$lt rt=$rt lx=$(Axis $LeftStick[0]) ly=$(Axis $LeftStick[1]) " +
        "rx=$(Axis $RightStick[0]) ry=$(Axis $RightStick[1]) dur=$($Seconds.ToString($inv))"
    [IO.File]::WriteAllText($file, $line)
    Start-Sleep -Milliseconds ([int](($Seconds + $Gap) * 1000))
}
