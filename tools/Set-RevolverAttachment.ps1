param(
    [switch]$Detach,
    [ValidateSet('Right90Pre','Left90Pre','Archived')][string]$Rotation = 'Right90Pre',
    [int]$Port = 8899
)
# Experimental session-only attachment from the user's Desktop profile archive.
# 'permanent' means gameplay transforms are changed; it does NOT persist this file.
$ErrorActionPreference = 'Stop'
$base = "http://127.0.0.1:$Port"
function Get-Bridge([string]$Route) {
    $data = Invoke-RestMethod ($base + $Route) -TimeoutSec 10
    if ($data.error) { throw $data.error }
    $data
}
if ((Get-Bridge '/api/game_info').gameName -ne 'AloneInTheDark-Win64-Shipping.exe') {
    throw 'Wrong game connected.'
}
$pawn = (Get-Bridge '/api/player').pawn.address
if (!$pawn) { throw 'No player pawn. Load a save first.' }
$weapon = (Get-Bridge "/api/explorer/method?address=$pawn&methodName=GetActiveWeapon").result
if ($weapon.className -ne 'BP_HitscanWeapon_Base_Revolver_C') { throw 'Select the revolver first.' }
$root = (Get-Bridge "/api/explorer/field?address=$($weapon.address)&fieldName=RootComponent").value
if ($root.className -ne 'SphereComponent') { throw 'Unexpected revolver root component.' }
if ($Detach) {
    $route = '/api/vr/detach'
    $body = @{address=$root.address}
} else {
    if (!(Get-Bridge '/api/vr/status').usingControllers) { throw 'Wake/track controllers before attaching.' }
    # Archived points the barrel right when the controller points forward on the
    # current build. Left90Pre then pointed the barrel back at the player. The
    # opposite Right90Pre correction is the current forward-facing candidate.
    $rotationOffsets = @{
        Archived = @{w=0.0291097462;x=0.7996023893;y=0.5982758999;z=0.0430645943}
        Left90Pre = @{w=0.4436286448;x=0.5349530051;y=0.4024612469;z=0.5958555384}
        Right90Pre = @{w=-0.4024612469031347;x=0.5958555383855734;y=0.4436286447764134;z=-0.5349530050684181}
    }
    $route = '/api/vr/attach'
    $body = @{
        address=$root.address; hand='right'; permanent=$true
        locationOffset=@{x=-3.98251152;y=2.8273344;z=5.70884609}
        rotationOffset=$rotationOffsets[$Rotation]
    }
}
$response = Invoke-RestMethod ($base + $route) -Method Post -ContentType 'application/json' -Body ($body | ConvertTo-Json -Depth 4) -TimeoutSec 10
if (!$response.success) { throw ($response | ConvertTo-Json -Compress) }
$response
