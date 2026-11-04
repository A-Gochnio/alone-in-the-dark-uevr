param([int]$Seconds = 300, [int]$IntervalMs = 200, [int]$Port = 8899)
# Bridge sampler for aim calibration: while the player aims, logs the weapon's gameplay trace
# (GetTraceStart/End), the weapon actor and muzzle transforms, the camera and the VR poses to
# local/aim-captures/aimlog-*.jsonl, one JSON line per sample. Samples are sequential reads,
# not atomic; hold the aim still while sampling.
$ErrorActionPreference = 'Stop'
$base = "http://127.0.0.1:$Port"
function Get-Bridge([string]$Route) { Invoke-RestMethod ($base + $Route) -TimeoutSec 5 }
function Get-Getter([string]$Address, [string]$Name) {
    (Get-Bridge "/api/explorer/method?address=$Address&methodName=$Name").result
}
$folder = Join-Path (Split-Path $PSScriptRoot) 'local/aim-captures'
New-Item -ItemType Directory -Path $folder -Force | Out-Null
$path = Join-Path $folder ('aimlog-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '.jsonl')
$deadline = [DateTime]::UtcNow.AddSeconds($Seconds)
$count = 0
while ([DateTime]::UtcNow -lt $deadline) {
    try {
        $pawn = (Get-Bridge '/api/player').pawn.address
        if ($pawn -and (Get-Getter $pawn 'IsAiming')) {
            $weapon = Get-Getter $pawn 'GetActiveWeapon'
            if ($weapon.className -match 'HitscanWeapon') {
                $a = $weapon.address
                $sample = [ordered]@{
                    t = (Get-Date).ToString('HH:mm:ss.fff')
                    weapon = $weapon.className
                    ammo = (Get-Bridge "/api/explorer/field?address=$a&fieldName=CurrentAmmo").value
                    traceStart = Get-Getter $a 'GetTraceStart'
                    traceEnd = Get-Getter $a 'GetTraceEnd'
                    actorLocation = Get-Getter $a 'K2_GetActorLocation'
                    actorForward = Get-Getter $a 'GetActorForwardVector'
                    actorRotation = Get-Getter $a 'K2_GetActorRotation'
                    camera = Get-Bridge '/api/camera'
                    poses = Get-Bridge '/api/vr/poses'
                }
                $sample | ConvertTo-Json -Depth 10 -Compress | Add-Content -LiteralPath $path -Encoding utf8
                $count++
            }
        }
    } catch { }
    Start-Sleep -Milliseconds $IntervalMs
}
"$count samples -> $path"
