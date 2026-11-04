[CmdletBinding()]
param(
    [ValidateRange(30, 600)]
    [int]$GameTimeoutSeconds = 180,
    [bool]$DirectX12 = $true,
    [switch]$SkipGraphicsProfile,
    [switch]$SkipQuestKeepAwake
)

$ErrorActionPreference = 'Stop'

$gameProcessName = 'AloneInTheDark-Win64-Shipping'
. (Join-Path $PSScriptRoot 'AitDCommon.ps1')
$gameExe = Get-AitDGameExe
$gameBin = Split-Path -Parent $gameExe
$injectorExe = Join-Path $env:APPDATA 'raicuparta\rai-pal\data\shared-mods\uevr-nightly\UEVRInjector.exe'
$profileDir = Join-Path $env:APPDATA 'UnrealVRMod\AloneInTheDark-Win64-Shipping'
$keepAwakeScript = Join-Path $PSScriptRoot '..\local\quest-keep-awake.ps1'
$graphicsScript = Join-Path $PSScriptRoot 'Set-AitDVRGraphics.ps1'
$stereoOptiState = Join-Path $PSScriptRoot '..\local\stereo-optiscaler-install.json'
$bridgeUrl = 'http://127.0.0.1:8899/api/game_info'

foreach ($requiredPath in @($gameExe, $injectorExe, $profileDir)) {
    if (!(Test-Path -LiteralPath $requiredPath)) {
        throw "Required path is missing: $requiredPath"
    }
}

if (!$SkipQuestKeepAwake -and (Test-Path -LiteralPath $keepAwakeScript)) {
    & $keepAwakeScript -Mode On -Continuous | Out-Host
}

$stereoLayerRequested = $false
$game = Get-Process -Name $gameProcessName -ErrorAction SilentlyContinue | Select-Object -First 1
if (!$game) {
    if (!$SkipGraphicsProfile) {
        & $graphicsScript -Mode Apply | Out-Host
    }

    if ($DirectX12) {
        $stereoLayerRequested = Test-Path -LiteralPath $stereoOptiState
        if ($stereoLayerRequested) {
            $env:XR_API_LAYER_PATH = $gameBin
            $env:XR_ENABLE_API_LAYERS = 'XR_APILAYER_XRFrameBridge_diagnostic'
            Write-Host 'Requesting the staged OFXR stereo frame-generation OpenXR layer for this launch...'
        }
        Write-Host 'Launching Alone in the Dark with -dx12...'
        Start-Process -FilePath $gameExe -ArgumentList '-dx12' -WorkingDirectory (Split-Path -Parent $gameExe)
    } else {
        Write-Host 'Launching Alone in the Dark through Steam with its default renderer...'
        Start-Process 'steam://rungameid/1310410'
    }

    $deadline = [DateTime]::UtcNow.AddSeconds($GameTimeoutSeconds)
    do {
        Start-Sleep -Milliseconds 500
        $game = Get-Process -Name $gameProcessName -ErrorAction SilentlyContinue | Select-Object -First 1
    } until ($game -or [DateTime]::UtcNow -ge $deadline)

    if (!$game) {
        throw "The game did not start within $GameTimeoutSeconds seconds."
    }
} else {
    Write-Host "Game is already running (PID $($game.Id))."
    $stereoLayerRequested = $false
}

$bridge = $null
try {
    $bridge = Invoke-RestMethod -Uri $bridgeUrl -TimeoutSec 2
} catch {
    # A failed bridge request is expected before UEVR injection.
}

if ($bridge -and $bridge.gameName -eq 'AloneInTheDark-Win64-Shipping.exe') {
    Write-Host "UEVR is already injected into PID $($game.Id)."
    [PSCustomObject]@{
        GamePid = $game.Id
        InjectorStarted = $false
        Injected = $true
        Runtime = $bridge.vrRuntime
        NextAction = 'Close the in-game UEVR overlay with Insert if it is visible.'
    }
    exit 0
}

$injector = Get-Process -Name 'UEVRInjector' -ErrorAction SilentlyContinue | Select-Object -First 1
if ($injector) {
    Write-Host "Restarting the stale UEVR injector process (PID $($injector.Id)) so it discovers the current game PID..."
    Stop-Process -Id $injector.Id
    $injector.WaitForExit(10000) | Out-Null
}
Write-Host 'Opening the pinned UEVR nightly injector...'
$injector = Start-Process -FilePath $injectorExe -WorkingDirectory (Split-Path -Parent $injectorExe) -PassThru

Write-Host ''
Write-Host 'Ready to inject (or run tools\Invoke-AitDUevrInject.ps1 instead):'
Write-Host '  1. Select AloneInTheDark-Win64-Shipping in UEVR.'
Write-Host '  2. Select OpenXR.'
Write-Host '  3. Click Inject.'
Write-Host '  4. Verify /api/game_info identifies this game and OpenXR.'
Write-Host '  5. Press Insert in the game if the UEVR overlay captured the controllers.'

[PSCustomObject]@{
    GamePid = $game.Id
    InjectorPid = $injector.Id
    InjectorStarted = $true
    Injected = $false
    RuntimeRequested = 'OpenXR'
    DirectX12Requested = $DirectX12
    StereoOpenXRLayerRequested = $stereoLayerRequested
    ProfileDirectory = $profileDir
}
