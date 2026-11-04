param([int]$Port = 8899)
# Testing cheat: gives Edward every firearm and ammo through the bridge (uevr_mcp.dll in the
# profile's plugins/). Item assets are looked up by path each run, since addresses change per launch.
$ErrorActionPreference = 'Stop'
$base = "http://127.0.0.1:$Port"
$items = [ordered]@{
    'Tommygun/IDE_Tommygun.IDE_Tommygun'                         = 1
    'Shotgun/IDE_Shotgun.IDE_Shotgun'                            = 1
    'Flaregun/IDE_FlareGun.IDE_FlareGun'                         = 1
    'Remington/IDE_Remington.IDE_Remington'                      = 1
    'Revolver/ID_Player_RevolverBullet.ID_Player_RevolverBullet' = 60
    'Shotgun/ID_Player_ShotgunShell.ID_Player_ShotgunShell'      = 40
    'Tommygun/ID_Player_TommygunBullet.ID_Player_TommygunBullet' = 200
    'Flaregun/ID_Player_Flare.ID_Player_Flare'                   = 20
    'Remington/ID_Player_RemingtonBullet.ID_Player_RemingtonBullet' = 40
}
function Find-Object([string]$Name) {
    $r = Invoke-RestMethod "$base/api/explorer/search?query=$([uri]::EscapeDataString($Name))&limit=5" -TimeoutSec 10
    ($r.results | Where-Object { $_.fullName.EndsWith($Name) } | Select-Object -First 1).address
}
$pawn = (Invoke-RestMethod "$base/api/player" -TimeoutSec 5).pawn.address
$lib = Find-Object 'Default__InventoryBlueprintLibrary'
foreach ($path in $items.Keys) {
    $item = Find-Object "/Game/ObsidianFox/Items/PlayerWeapons/$path"
    if (!$item) { Write-Warning "Not loaded: $path"; continue }
    $body = @{ address = $lib; methodName = 'AddItemToInventory'
        args = @{ WorldContextObject = $pawn; ItemData = $item; Amount = $items[$path]; PopUp = 0 } } | ConvertTo-Json -Depth 4
    $r = Invoke-RestMethod "$base/api/explorer/method" -Method Post -Body $body -ContentType 'application/json' -TimeoutSec 10
    '{0} x{1}: {2}' -f ($path -split '/')[0], $items[$path], $r.result
}
