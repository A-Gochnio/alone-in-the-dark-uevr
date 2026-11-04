param([int]$Port = 8899, [int]$Iterations = 3, [double]$ProbeAngle = 3.0, [double]$ProbeCm = 2.0,
    [ValidateSet('MuzzleFlash', 'Mesh')] [string]$Reference = 'MuzzleFlash',
    [switch]$AngleOnly)
# Live revolver barrel calibration through the bridge. While the player holds aim, measures how
# the visible barrel deviates from the gameplay shot ray (GetTraceStart -> GetTraceEnd):
#   - angle: the ray direction's two components across the barrel axis;
#   - position: the muzzle's distance from the ray (cm), along the same two cross axes.
# The barrel reference is the muzzle-flash component (forward = barrel, default; Arek saw the mesh
# +Y axis, which the Arrow shares, still ~10 deg off). It probes the trims that
# alone_in_the_dark_vr.lua reads live from data/aitd_aim_tune.txt (pitch, yaw in degrees; lx, ly,
# lz in cm), solves the least-squares step from the measured Jacobian and writes the result.
# With only the angle matched the dot drifted sideways as the target got closer, because the ray
# starts off the barrel; matching the position as well keeps the dot on the barrel line.
$ErrorActionPreference = 'Stop'
$inv = [Globalization.CultureInfo]::InvariantCulture
$base = "http://127.0.0.1:$Port"
$tune = Join-Path $env:APPDATA 'UnrealVRMod\AloneInTheDark-Win64-Shipping\data\aitd_aim_tune.txt'
$keys = @('pitch', 'yaw', 'lx', 'ly', 'lz')
function Get-Bridge([string]$Route) { Invoke-RestMethod ($base + $Route) -TimeoutSec 5 }
function Get-Getter([string]$Address, [string]$Name) {
    (Get-Bridge "/api/explorer/method?address=$Address&methodName=$Name").result
}
function Set-Trim([double[]]$p) {
    $lines = for ($i = 0; $i -lt $keys.Count; $i++) { [string]::Format($inv, '{0}={1}', $keys[$i], [math]::Round($p[$i], 3)) }
    Set-Content -LiteralPath $tune -Value ($lines -join "`n") -Encoding ascii
    Start-Sleep -Milliseconds 700
}
function Dot($a, $b) { [double]$a[0] * $b.x + [double]$a[1] * $b.y + [double]$a[2] * $b.z }
function Measure-Error {
    $rows = @()
    $deadline = [DateTime]::UtcNow.AddSeconds(180)
    while ($rows.Count -lt 6 -and [DateTime]::UtcNow -lt $deadline) {
        $pawn = (Get-Bridge '/api/player').pawn.address
        if (!(Get-Getter $pawn 'IsAiming')) { Start-Sleep -Milliseconds 300; continue }
        $w = (Get-Getter $pawn 'GetActiveWeapon').address
        $field = if ($Reference -eq 'Mesh') { 'SkeletalMesh' } else { 'MuzzleFlash' }
        $c = (Get-Bridge "/api/explorer/field?address=$w&fieldName=$field").value.address
        $s = Get-Getter $w 'GetTraceStart'; $e = Get-Getter $w 'GetTraceEnd'
        $d = @(([double]$e.x - $s.x), ([double]$e.y - $s.y), ([double]$e.z - $s.z))
        $l = [math]::Sqrt($d[0] * $d[0] + $d[1] * $d[1] + $d[2] * $d[2]); $d = @(($d[0] / $l), ($d[1] / $l), ($d[2] / $l))
        # Two axes across the barrel: mesh +X/+Z for the mesh (+Y is the barrel), right/up for the flash.
        $a1 = Get-Getter $c $(if ($Reference -eq 'Mesh') { 'GetForwardVector' } else { 'GetRightVector' })
        $a2 = Get-Getter $c 'GetUpVector'
        $m = Get-Getter $c 'K2_GetComponentLocation'
        $v = @(([double]$m.x - $s.x), ([double]$m.y - $s.y), ([double]$m.z - $s.z))
        $along = $v[0] * $d[0] + $v[1] * $d[1] + $v[2] * $d[2]
        $perp = @(($v[0] - $along * $d[0]), ($v[1] - $along * $d[1]), ($v[2] - $along * $d[2]))
        $rows += , @((Dot $d $a1), (Dot $d $a2), (Dot $perp $a1), (Dot $perp $a2))
        Start-Sleep -Milliseconds 120
    }
    if ($rows.Count -lt 6) { throw 'Not aiming: hold the right grip with the revolver drawn.' }
    $avg = @(0.0, 0.0, 0.0, 0.0)
    foreach ($r in $rows) { for ($i = 0; $i -lt 4; $i++) { $avg[$i] += $r[$i] / $rows.Count } }
    # Angle components in radians, scaled to "cm at 1 m" so both kinds weigh alike.
    @(($avg[0] * 100), ($avg[1] * 100), $avg[2], $avg[3])
}
function Solve([double[][]]$A, [double[]]$b) {
    # Gaussian elimination with partial pivoting on a small square system.
    $n = $b.Count
    $M = for ($i = 0; $i -lt $n; $i++) { , ([double[]](@($A[$i]) + @($b[$i]))) }
    for ($c = 0; $c -lt $n; $c++) {
        $p = $c; for ($r = $c + 1; $r -lt $n; $r++) { if ([math]::Abs($M[$r][$c]) -gt [math]::Abs($M[$p][$c])) { $p = $r } }
        $tmp = $M[$c]; $M[$c] = $M[$p]; $M[$p] = $tmp
        if ([math]::Abs($M[$c][$c]) -lt 1e-12) { throw 'Singular calibration system.' }
        for ($r = 0; $r -lt $n; $r++) {
            if ($r -eq $c) { continue }
            $f = $M[$r][$c] / $M[$c][$c]
            for ($k = $c; $k -le $n; $k++) { $M[$r][$k] -= $f * $M[$c][$k] }
        }
    }
    for ($i = 0; $i -lt $n; $i++) { $M[$i][$n] / $M[$i][$i] }
}

$text = Get-Content -LiteralPath $tune -Raw
[double[]]$p = foreach ($k in $keys) {
    $m = [regex]::Match($text, "(?m)^$k\s*=\s*([-\d.]+)")
    if ($m.Success) { [double]::Parse($m.Groups[1].Value, $inv) } else { 0.0 }
}
# A failed run (aim released, bridge error) must not leave a probe trim in the tune file.
$orig = [double[]]$p.Clone()
trap { Set-Trim $orig; break }
$active = if ($AngleOnly) { @(0, 1) } else { @(0, 1, 2, 3, 4) }
$rowsUsed = if ($AngleOnly) { @(0, 1) } else { @(0, 1, 2, 3) }
for ($it = 1; $it -le $Iterations; $it++) {
    Set-Trim $p
    $e0 = Measure-Error
    '{0}: pitch {1:N2} yaw {2:N2} loc ({3:N1}, {4:N1}, {5:N1}) -> angle {6:N2} deg, muzzle off ray {7:N1} cm' -f $it, $p[0], $p[1], $p[2], $p[3], $p[4],
        ([math]::Sqrt($e0[0] * $e0[0] + $e0[1] * $e0[1]) / 100 * 180 / [math]::PI), [math]::Sqrt($e0[2] * $e0[2] + $e0[3] * $e0[3])
    # Jacobian columns: change of each used error component per unit of each active trim.
    $Jac = @{}
    foreach ($j in $active) {
        $q = [double[]]$p.Clone(); $h = if ($j -lt 2) { $ProbeAngle } else { $ProbeCm }; $q[$j] += $h
        Set-Trim $q
        $ej = Measure-Error
        $Jac[$j] = [double[]]@(foreach ($r in $rowsUsed) { ($ej[$r] - $e0[$r]) / $h })
    }
    # Minimum-norm least squares: dx = J^T (J J^T)^-1 (-e).
    $nR = $rowsUsed.Count
    $JJt = [double[][]]@(for ($a = 0; $a -lt $nR; $a++) { , [double[]]@(for ($b = 0; $b -lt $nR; $b++) { $s = 0.0; foreach ($j in $active) { $s += $Jac[$j][$a] * $Jac[$j][$b] }; $s }) })
    $rhs = [double[]]@(foreach ($r in $rowsUsed) { - $e0[$r] })
    $y = @(Solve $JJt $rhs)
    foreach ($j in $active) { $s = 0.0; for ($a = 0; $a -lt $nR; $a++) { $s += $Jac[$j][$a] * $y[$a] }; $p[$j] += $s }
}
Set-Trim $p
$final = Measure-Error
$summary = for ($i = 0; $i -lt $keys.Count; $i++) { [string]::Format($inv, '{0}={1}', $keys[$i], [math]::Round($p[$i], 3)) }
'final: ' + ($summary -join ' ') + (' | angle {0:N2} deg, muzzle off ray {1:N1} cm' -f ([math]::Sqrt($final[0] * $final[0] + $final[1] * $final[1]) / 100 * 180 / [math]::PI), [math]::Sqrt($final[2] * $final[2] + $final[3] * $final[3]))
