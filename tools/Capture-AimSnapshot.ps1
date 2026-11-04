param([string]$Label = 'snapshot', [int]$Port = 8899)
# Read-only bridge diagnostics. Addresses are discovered anew for each capture.
$ErrorActionPreference = 'Stop'
$base = "http://127.0.0.1:$Port"
function Read-Bridge([string]$Route) {
    $result = Invoke-RestMethod ($base + $Route) -TimeoutSec 10
    if ($result.error) { throw $result.error }
    return $result
}
function Read-Field([string]$Address, [string]$Name) {
    (Read-Bridge "/api/explorer/field?address=$Address&fieldName=$Name").value
}
function Read-Getter([string]$Address, [string]$Name) {
    (Read-Bridge "/api/explorer/method?address=$Address&methodName=$Name").result
}
$identity = Read-Bridge '/api/game_info'
if ($identity.gameName -ne 'AloneInTheDark-Win64-Shipping.exe') {
    throw 'Bridge is not connected to Alone in the Dark.'
}
$player = Read-Bridge '/api/player'
$pawnAddress = $player.pawn.address
if (!$pawnAddress) { throw 'Load a save before capturing aiming state.' }
$weapon = Read-Getter $pawnAddress 'GetActiveWeapon'
$capture = [ordered]@{
    capturedAt = (Get-Date).ToString('o')
    label = $Label
    note = 'Sequential getter samples, not an atomic frame or proof of a fired hit.'
    game = $identity
    player = $player
    vrStatus = Read-Bridge '/api/vr/status'
    poses = Read-Bridge '/api/vr/poses'
    settings = Read-Bridge '/api/vr/settings'
    camera = Read-Bridge '/api/camera'
    isAiming = Read-Getter $pawnAddress 'IsAiming'
    weapon = $weapon
}
if ($weapon.address) {
    $address = $weapon.address
    $capture.weaponState = [ordered]@{}
    foreach ($field in @('CurrentAmmo','bIsHolstered','Aiming','RootComponent','SkeletalMesh')) {
        $capture.weaponState[$field] = Read-Field $address $field
    }
    # Only HitscanWeapon exposes these getters; don't invoke them on melee items.
    if ($weapon.className -match 'HitscanWeapon') {
        $capture.traceStart = Read-Getter $address 'GetTraceStart'
        $capture.traceEnd = Read-Getter $address 'GetTraceEnd'
    }
    $capture.weaponLocation = Read-Getter $address 'K2_GetActorLocation'
    $capture.weaponForward = Read-Getter $address 'GetActorForwardVector'
}
$folder = Join-Path (Split-Path $PSScriptRoot) 'local/aim-captures'
New-Item -ItemType Directory -Path $folder -Force | Out-Null
$safeLabel = $Label -replace '[^a-zA-Z0-9_-]', '_'
$path = Join-Path $folder ((Get-Date -Format 'yyyyMMdd-HHmmss-fff') + '-' + $safeLabel + '.json')
$capture | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $path -Encoding utf8
Write-Output $path
