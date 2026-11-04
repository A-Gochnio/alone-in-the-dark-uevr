param(
    [ValidateRange(2, 120)]
    [int]$Seconds = 15,
    [ValidateRange(50, 2000)]
    [int]$IntervalMs = 100,
    [int]$Port = 8899
)
# Samples UEVR's VR joystick values next to Edward's location and control yaw while the user pushes the sticks.
# Non-zero joysticks without movement point at the XInput/game side; zero joysticks point at OpenXR/Virtual Desktop.
$ErrorActionPreference = 'Stop'
$base = "http://127.0.0.1:$Port"

$identity = Invoke-RestMethod "$base/api/game_info" -TimeoutSec 5
if ($identity.gameName -ne 'AloneInTheDark-Win64-Shipping.exe') { throw 'Bridge is not connected to Alone in the Dark.' }
$player = Invoke-RestMethod "$base/api/player" -TimeoutSec 5
if (!$player.pawn.address) { throw 'Load a save before sampling.' }
$pawn = $player.pawn.address
$controller = $player.controller.address

$samples = New-Object System.Collections.Generic.List[object]
$deadline = [DateTime]::UtcNow.AddSeconds($Seconds)
while ([DateTime]::UtcNow -lt $deadline) {
    $vrInput = Invoke-RestMethod "$base/api/vr/input" -TimeoutSec 2
    $location = (Invoke-RestMethod "$base/api/explorer/method?address=$pawn&methodName=K2_GetActorLocation" -TimeoutSec 2).result
    $rotation = (Invoke-RestMethod "$base/api/explorer/method?address=$controller&methodName=GetControlRotation" -TimeoutSec 2).result
    $samples.Add([PSCustomObject]@{
        Time = [DateTime]::Now.ToString('HH:mm:ss.fff')
        UsingControllers = $vrInput.usingControllers
        LX = [Math]::Round($vrInput.leftJoystick.x, 2); LY = [Math]::Round($vrInput.leftJoystick.y, 2)
        RX = [Math]::Round($vrInput.rightJoystick.x, 2); RY = [Math]::Round($vrInput.rightJoystick.y, 2)
        X = [Math]::Round($location.x, 1); Y = [Math]::Round($location.y, 1)
        Yaw = [Math]::Round($rotation.y, 2)
    })
    Start-Sleep -Milliseconds $IntervalMs
}

$first = $samples[0]; $last = $samples[$samples.Count - 1]
$folder = Join-Path (Split-Path $PSScriptRoot) 'local/stick-captures'
New-Item -ItemType Directory -Path $folder -Force | Out-Null
$path = Join-Path $folder ((Get-Date -Format 'yyyyMMdd-HHmmss') + '.csv')
$samples | Export-Csv -LiteralPath $path -NoTypeInformation -Encoding utf8

[PSCustomObject]@{
    Samples = $samples.Count
    UsingControllersSeen = @($samples | Where-Object UsingControllers).Count
    MaxAbsLeftStick = ($samples | ForEach-Object { [Math]::Max([Math]::Abs($_.LX), [Math]::Abs($_.LY)) } | Measure-Object -Maximum).Maximum
    MaxAbsRightStick = ($samples | ForEach-Object { [Math]::Max([Math]::Abs($_.RX), [Math]::Abs($_.RY)) } | Measure-Object -Maximum).Maximum
    Distance = [Math]::Round([Math]::Sqrt([Math]::Pow($last.X - $first.X, 2) + [Math]::Pow($last.Y - $first.Y, 2)), 1)
    YawDelta = [Math]::Round($last.Yaw - $first.Yaw, 2)
    Csv = $path
}

