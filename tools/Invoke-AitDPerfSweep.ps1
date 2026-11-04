param(
    [ValidateRange(5, 60)]
    [int]$Seconds = 12,
    [int]$SettleSeconds = 5,
    [string[]]$Only,          # run only the named steps
    [switch]$KeepLast,        # leave the last step applied instead of restoring the starting values
    [int]$Port = 8899
)
# Applies a sequence of live (non-persistent) UEVR and console-variable settings and measures each one with
# Measure-AitDPerf.ps1. Nothing is written to config.txt, GameUserSettings.ini or settings.sav; the starting
# values are restored at the end unless -KeepLast is given. Only results with valid=True (headset worn and
# Virtual Desktop streaming) are absolute FPS numbers; otherwise compare gpuMsPerVrFrame between steps only.
$ErrorActionPreference = 'Stop'
$base = "http://127.0.0.1:$Port"

# Every step is complete on its own (stock values are listed explicitly), so -Only can apply any one of them.
$stock = [ordered]@{ 'r.NGX.DLSS.Quality' = 2; 'r.VolumetricFog' = 1; 'r.ContactShadows' = 1; 'r.CapsuleShadows' = 1
    'r.BloomQuality' = 4; 'r.MotionBlurQuality' = 3; 'r.EyeAdaptationQuality' = 2; 'sg.ShadowQuality' = 1 }
$lowFx = @{ 'r.ContactShadows' = 0; 'r.CapsuleShadows' = 0; 'r.BloomQuality' = 1; 'r.MotionBlurQuality' = 0; 'r.EyeAdaptationQuality' = 0 }
function New-Step([string]$Name, [int]$Method, [hashtable[]]$Overrides) {
    $c = [ordered]@{}; foreach ($k in $stock.Keys) { $c[$k] = $stock[$k] }
    foreach ($o in $Overrides) { foreach ($k in $o.Keys) { $c[$k] = $o[$k] } }
    @{ Name = $Name; Uevr = @{ VR_RenderingMethod = $Method }; CVar = $c }
}
$steps = @(
    New-Step 'ss-dlss2' 1 @()
    New-Step 'ns-dlss2' 0 @()
    New-Step 'ns-dlss0' 0 @(@{ 'r.NGX.DLSS.Quality' = 0 })
    New-Step 'ns-dlss-1' 0 @(@{ 'r.NGX.DLSS.Quality' = -1 })
    New-Step 'ns-dlss0-novolfog' 0 @(@{ 'r.NGX.DLSS.Quality' = 0; 'r.VolumetricFog' = 0 })
    New-Step 'ns-dlss0-lowfx' 0 @(@{ 'r.NGX.DLSS.Quality' = 0 }, $lowFx)
    New-Step 'ns-dlss0-lowfx-sh0' 0 @(@{ 'r.NGX.DLSS.Quality' = 0; 'sg.ShadowQuality' = 0 }, $lowFx)
    New-Step 'ns-dlss-1-lowfx-sh0' 0 @(@{ 'r.NGX.DLSS.Quality' = -1; 'sg.ShadowQuality' = 0 }, $lowFx)
    New-Step 'ns-dlss2-lowfx-sh0' 0 @(@{ 'sg.ShadowQuality' = 0 }, $lowFx)
)
if ($Only) { $steps = $steps | Where-Object { $Only -contains $_.Name } }

function Get-CVar([string]$Name) { (Invoke-RestMethod "$base/api/console/cvar?name=$Name" -TimeoutSec 5).float }
function Set-CVar([string]$Name, $Value) {
    $body = @{ name = $Name; value = [double]$Value } | ConvertTo-Json -Compress
    Invoke-RestMethod -Method Post "$base/api/console/cvar" -Body $body -ContentType 'application/json' -TimeoutSec 5 | Out-Null
}
function Set-Uevr([string]$Key, $Value) {
    $body = @{ key = $Key; value = "$Value" } | ConvertTo-Json -Compress
    Invoke-RestMethod -Method Post "$base/api/vr/settings" -Body $body -ContentType 'application/json' -TimeoutSec 5 | Out-Null
}

$configPath = Join-Path $env:APPDATA 'UnrealVRMod\AloneInTheDark-Win64-Shipping\config.txt'
$startMethod = if ($env:AITD_RENDERING_METHOD) { [int]$env:AITD_RENDERING_METHOD } else {
    [int]((Get-Content $configPath | Where-Object { $_ -like 'VR_RenderingMethod=*' }) -split '=')[1] }
$cvarNames = $steps | ForEach-Object { $_.CVar.Keys } | Sort-Object -Unique
$original = @{}
foreach ($n in $cvarNames) { $original[$n] = Get-CVar $n }

$method = $startMethod
$results = foreach ($step in $steps) {
    foreach ($k in $step.Uevr.Keys) { Set-Uevr $k $step.Uevr[$k]; if ($k -eq 'VR_RenderingMethod') { $method = $step.Uevr[$k] } }
    foreach ($k in $step.CVar.Keys) { Set-CVar $k $step.CVar[$k] }
    Start-Sleep -Seconds $SettleSeconds
    $env:AITD_RENDERING_METHOD = "$method"
    & (Join-Path $PSScriptRoot 'Measure-AitDPerf.ps1') -Label "sweep-$($step.Name)" -Seconds $Seconds -Port $Port
}

if (!$KeepLast) {
    foreach ($n in $original.Keys) { Set-CVar $n $original[$n] }
    Set-Uevr 'VR_RenderingMethod' $startMethod
    $env:AITD_RENDERING_METHOD = "$startMethod"
}
$results | Select-Object label, valid, renderingMethod, vrFps, engineMsP95, gpu3dBusyPct, gpuMsPerVrFrame, gpuClockAvg,
    @{ n = 'gpuWork'; e = { [math]::Round($_.gpuMsPerVrFrame * $_.gpuClockAvg / 1000, 1) } } | Format-Table -AutoSize
