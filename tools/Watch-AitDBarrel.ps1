param([int]$Seconds = 180, [int]$Port = 8899)
# Bridge sampler for barrel calibration and menu placement. While aiming it logs the gameplay
# trace and the forward/right/up axes of the revolver mesh, its Arrow and its muzzle-flash
# component; at all times it logs the HMD pose, control rotation and the game's main UI state.
# Output: local/aim-captures/barrel-*.jsonl.
$ErrorActionPreference = 'Stop'
$base = "http://127.0.0.1:$Port"
function Get-Bridge([string]$Route) { Invoke-RestMethod ($base + $Route) -TimeoutSec 5 }
function Get-Getter([string]$Address, [string]$Name) {
    (Get-Bridge "/api/explorer/method?address=$Address&methodName=$Name").result
}
function Get-Axes([string]$Address) {
    [ordered]@{
        f = Get-Getter $Address 'GetForwardVector'
        r = Get-Getter $Address 'GetRightVector'
        u = Get-Getter $Address 'GetUpVector'
    }
}
$folder = Join-Path (Split-Path $PSScriptRoot) 'local/aim-captures'
New-Item -ItemType Directory -Path $folder -Force | Out-Null
$path = Join-Path $folder ('barrel-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '.jsonl')
$playState = ((Get-Bridge '/api/explorer/search?query=GameSubsystem_PlayState_0&limit=5').results |
    Where-Object { $_.fullName -match 'Transient' } | Select-Object -First 1).address
$deadline = [DateTime]::UtcNow.AddSeconds($Seconds)
$count = 0
while ([DateTime]::UtcNow -lt $deadline) {
    try {
        $player = Get-Bridge '/api/player'
        $pawn = $player.pawn.address
        $sample = [ordered]@{
            t = (Get-Date).ToString('HH:mm:ss.fff')
            state = if ($playState) { (Get-Getter $playState 'GetMainState').value } else { $null }
            control = Get-Getter $player.controller.address 'GetControlRotation'
            poses = Get-Bridge '/api/vr/poses'
        }
        if ($pawn -and (Get-Getter $pawn 'IsAiming')) {
            $weapon = Get-Getter $pawn 'GetActiveWeapon'
            $a = $weapon.address
            $sample.traceStart = Get-Getter $a 'GetTraceStart'
            $sample.traceEnd = Get-Getter $a 'GetTraceEnd'
            foreach ($field in @('SkeletalMesh', 'Arrow', 'MuzzleFlash')) {
                $component = (Get-Bridge "/api/explorer/field?address=$a&fieldName=$field").value.address
                if ($component) { $sample[$field] = Get-Axes $component }
            }
        }
        $sample | ConvertTo-Json -Depth 10 -Compress | Add-Content -LiteralPath $path -Encoding utf8
        $count++
    } catch { }
    Start-Sleep -Milliseconds 250
}
"$count samples -> $path"
