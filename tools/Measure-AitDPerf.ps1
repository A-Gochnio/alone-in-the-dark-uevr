param(
    [string]$Label = 'sample',
    [ValidateRange(3, 120)]
    [int]$Seconds = 15,
    [int]$Port = 8899,
    # Without the uevr-mcp bridge (which caps the game at ~42 FPS), tick timing comes from the UEVR Lua logger
    # profile/scripts/aitd_perf_log.lua, which must be installed in the profile's scripts folder.
    [switch]$NoBridge
)
# Samples engine frame timing with the CSV profiler (csvprofile start/stop through the uevr-mcp bridge), the game's own 3D-engine busy time
# (Windows GPU Engine counter, no admin needed), GPU clocks, and whether the headset is actually streaming.
# In UEVR Synchronized Sequential mode (VR_RenderingMethod=1) one VR frame takes two engine ticks; in Native
# Stereo (0) it takes one. Numbers are only valid when 'valid' is true: with the headset asleep or Virtual
# Desktop disconnected, the OpenXR runtime paces the engine and the GPU idles at low clocks.
$ErrorActionPreference = 'Stop'
$base = "http://127.0.0.1:$Port"

function Invoke-Console([string]$Command) {
    $body = @{ command = $Command } | ConvertTo-Json -Compress
    Invoke-RestMethod -Method Post -Uri "$base/api/console/command" -Body $body -ContentType 'application/json' -TimeoutSec 5 | Out-Null
}

function Get-SentBytes { (Get-NetAdapterStatistics | Measure-Object SentBytes -Sum).Sum }

if (!$NoBridge) {
    $identity = Invoke-RestMethod "$base/api/game_info" -TimeoutSec 5
    if ($identity.gameName -ne 'AloneInTheDark-Win64-Shipping.exe') { throw 'Bridge is not connected to Alone in the Dark.' }
}
$gamePid = (Get-Process AloneInTheDark-Win64-Shipping | Select-Object -First 1).Id
$method = [int]((Get-Content (Join-Path $env:APPDATA 'UnrealVRMod\AloneInTheDark-Win64-Shipping\config.txt') |
    Where-Object { $_ -like 'VR_RenderingMethod=*' }) -split '=')[1]
# The live value can differ from config.txt after a bridge change; the sweep passes it through the label instead.
if ($env:AITD_RENDERING_METHOD) { $method = [int]$env:AITD_RENDERING_METHOD }
$ticksPerVrFrame = if ($method -eq 1) { 2 } else { 1 }
$folder = Join-Path (Split-Path $PSScriptRoot) 'local/perf'
$safe = $Label -replace '[^a-zA-Z0-9_-]', '_'

if ($NoBridge) {
    $perfLog = Join-Path $env:APPDATA 'UnrealVRMod\AloneInTheDark-Win64-Shipping\data\aitd_perf.csv'
    if (!(Test-Path -LiteralPath $perfLog)) { throw "No tick log at $perfLog; install profile/scripts/aitd_perf_log.lua and reinject." }
    $counter = "\GPU Engine(pid_${gamePid}_*engtype_3D)\Running Time"
    $from = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    $sent0 = Get-SentBytes
    $busy0 = (Get-Counter $counter).CounterSamples | Measure-Object RawValue -Sum
    $t0 = [DateTime]::UtcNow
    $gpu = New-Object System.Collections.Generic.List[object]
    while (([DateTime]::UtcNow - $t0).TotalSeconds -lt $Seconds) {
        $line = (& nvidia-smi --query-gpu=utilization.gpu,clocks.gr,power.draw,encoder.stats.averageFps --format=csv,noheader,nounits) -split ',\s*'
        $gpu.Add([PSCustomObject]@{ Util = [double]$line[0]; Clock = [double]$line[1]; Power = [double]$line[2]; EncFps = [double]$line[3] })
        Start-Sleep -Milliseconds 500
    }
    $elapsed = ([DateTime]::UtcNow - $t0).TotalSeconds
    $busy1 = (Get-Counter $counter).CounterSamples | Measure-Object RawValue -Sum
    $mbit = ((Get-SentBytes) - $sent0) * 8 / $elapsed / 1e6
    Start-Sleep -Seconds 2
    $inv = [Globalization.CultureInfo]::InvariantCulture
    # Lua log rows: unix time, ticks, avg ms, p95 ms, max ms for each 2 s window.
    $rows = @(Get-Content -LiteralPath $perfLog | ForEach-Object { $f = $_ -split ','; [PSCustomObject]@{
        T = [long]$f[0]; N = [int]$f[1]; Avg = [double]::Parse($f[2], $inv); P95 = [double]::Parse($f[3], $inv); Max = [double]::Parse($f[4], $inv) } } |
        Where-Object { $_.T -gt $from -and $_.T -le $from + $Seconds + 1 })
    if ($rows.Count -eq 0) { throw 'The tick log has no rows for this window.' }
    $ticks = ($rows | Measure-Object N -Sum).Sum
    $avgMs = (($rows | ForEach-Object { $_.N * $_.Avg }) | Measure-Object -Sum).Sum / $ticks
    $busyMs = ($busy1.Sum - $busy0.Sum) / 1e4
    $result = [ordered]@{
        capturedAt = (Get-Date).ToString('o')
        label = $Label
        seconds = $Seconds
        source = 'lua-tick-log'
        valid = $mbit -gt 5
        streamMbit = [math]::Round($mbit, 1)
        renderingMethod = $method
        engineTicks = $ticks
        engineFps = [math]::Round(1000.0 / $avgMs, 1)
        vrFps = [math]::Round(1000.0 / $avgMs / $ticksPerVrFrame, 1)
        engineMsAvg = [math]::Round($avgMs, 2)
        engineMsP95Worst = ($rows | Measure-Object P95 -Maximum).Maximum
        engineMsMax = ($rows | Measure-Object Max -Maximum).Maximum
        encoderFps = [math]::Round(($gpu | Measure-Object EncFps -Average).Average, 1)
        gpu3dBusyPct = [math]::Round(100.0 * $busyMs / ($elapsed * 1000.0), 1)
        gpuMsPerVrFrame = [math]::Round($busyMs / ($elapsed * 1000.0 / $avgMs / $ticksPerVrFrame), 2)
        gpuUtilAvg = [math]::Round(($gpu | Measure-Object Util -Average).Average, 1)
        gpuClockAvg = [math]::Round(($gpu | Measure-Object Clock -Average).Average)
        gpuPowerAvg = [math]::Round(($gpu | Measure-Object Power -Average).Average, 1)
    }
    New-Item -ItemType Directory -Path $folder -Force | Out-Null
    $result | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $folder ((Get-Date -Format 'yyyyMMdd-HHmmss') + "-$safe.json")) -Encoding utf8
    if (!$result.valid) { Write-Warning "$Label is not a valid VR measurement: the headset is not streaming ($([math]::Round($mbit,1)) Mbit/s)." }
    return [PSCustomObject]$result
}

# Engine frame times come from the CSV profiler. A Lua frame callback undercounted ticks (32/s against the
# profiler's 42/s on 2026-10-24), so it is no longer used.
$csvDir = Join-Path $env:LOCALAPPDATA 'AloneInTheDark\Saved\Profiling\CSV'
$csvStart = Get-Date
Invoke-Console 'csvprofile start'

$poseKeys = New-Object System.Collections.Generic.HashSet[string]
$controllers = 0; $polls = 0
$gpu = New-Object System.Collections.Generic.List[object]
$counter = "\GPU Engine(pid_${gamePid}_*engtype_3D)\Running Time"
$sent0 = Get-SentBytes
$busy0 = (Get-Counter $counter).CounterSamples | Measure-Object RawValue -Sum
$t0 = [DateTime]::UtcNow
$deadline = $t0.AddSeconds($Seconds)
while ([DateTime]::UtcNow -lt $deadline) {
    $line = (& nvidia-smi --query-gpu=utilization.gpu,clocks.gr,power.draw,memory.used --format=csv,noheader,nounits) -split ',\s*'
    $gpu.Add([PSCustomObject]@{ Util = [double]$line[0]; Clock = [double]$line[1]; Power = [double]$line[2]; Mem = [double]$line[3] })
    $poses = Invoke-RestMethod "$base/api/vr/poses" -TimeoutSec 2
    [void]$poseKeys.Add(($poses.hmd.rotation | ConvertTo-Json -Compress))
    if ((Invoke-RestMethod "$base/api/vr/status" -TimeoutSec 2).usingControllers) { $controllers++ }
    $polls++
    Start-Sleep -Milliseconds 400
}
$elapsed = ([DateTime]::UtcNow - $t0).TotalSeconds
$busy1 = (Get-Counter $counter).CounterSamples | Measure-Object RawValue -Sum
$mbit = ((Get-SentBytes) - $sent0) * 8 / $elapsed / 1e6

Invoke-Console 'csvprofile stop'
$csvFile = $null
for ($i = 0; $i -lt 40 -and !$csvFile; $i++) {
    Start-Sleep -Milliseconds 250
    $csvFile = Get-ChildItem $csvDir -Filter *.csv | Where-Object { $_.CreationTime -ge $csvStart.AddSeconds(-1) } |
        Sort-Object LastWriteTime -Descending | Select-Object -First 1
    # The profiler writes the file asynchronously; it is complete once the metadata row is present.
    if ($csvFile -and !((Get-Content $csvFile.FullName -Tail 1) -like '*HasHeaderRowAtEnd*')) { $csvFile = $null }
}
if (!$csvFile) { throw 'CSV profile was not written.' }
$inv = [Globalization.CultureInfo]::InvariantCulture
$frames = @(Import-Csv $csvFile.FullName | Select-Object -SkipLast 2)
function Get-ColumnAvg([string]$Name) { [math]::Round(($frames | ForEach-Object { [double]::Parse($_.$Name, $inv) } | Measure-Object -Average).Average, 2) }
$d = @($frames | ForEach-Object { [double]::Parse($_.FrameTime, $inv) } | Sort-Object)
function Get-Pct([double]$q) { if ($d.Count -eq 0) { 0 } else { $d[[math]::Min($d.Count - 1, [math]::Floor($d.Count * $q))] / 1000.0 } }
$s = [PSCustomObject]@{ n = $d.Count; p50 = Get-Pct 0.5; p95 = Get-Pct 0.95; p99 = Get-Pct 0.99; max = Get-Pct 1 }
$avgMs = ($d | Measure-Object -Average).Average
# Running Time is cumulative 100 ns units of 3D-engine work for this process.
$busyMs = ($busy1.Sum - $busy0.Sum) / 1e4
$ticks = [math]::Max(1, $s.n)
$headsetLive = ($poseKeys.Count -gt 3) -and ($mbit -gt 5)
$result = [ordered]@{
    capturedAt = (Get-Date).ToString('o')
    label = $Label
    seconds = $Seconds
    valid = $headsetLive
    hmdPoseDistinct = $poseKeys.Count
    controllersActivePct = [math]::Round(100.0 * $controllers / [math]::Max(1, $polls))
    streamMbit = [math]::Round($mbit, 1)
    renderingMethod = $method
    engineTicks = $s.n
    engineFps = if ($avgMs -gt 0) { [math]::Round(1000.0 / $avgMs, 1) } else { 0 }
    vrFps = if ($avgMs -gt 0) { [math]::Round(1000.0 / $avgMs / $ticksPerVrFrame, 1) } else { 0 }
    engineMsAvg = [math]::Round($avgMs, 2)
    engineMsP50 = [math]::Round(1000.0 * $s.p50, 2)
    engineMsP95 = [math]::Round(1000.0 * $s.p95, 2)
    engineMsP99 = [math]::Round(1000.0 * $s.p99, 2)
    engineMsMax = [math]::Round(1000.0 * $s.max, 2)
    gameThreadMs = Get-ColumnAvg 'GameThreadTime'
    renderThreadMs = Get-ColumnAvg 'RenderThreadTime'
    rhiThreadMs = Get-ColumnAvg 'RHIThreadTime'
    gpu3dBusyPct = [math]::Round(100.0 * $busyMs / ($elapsed * 1000.0), 1)
    gpuMsPerVrFrame = [math]::Round($busyMs / $ticks * $ticksPerVrFrame, 2)
    gpuUtilAvg = [math]::Round(($gpu | Measure-Object Util -Average).Average, 1)
    gpuClockAvg = [math]::Round(($gpu | Measure-Object Clock -Average).Average)
    gpuPowerAvg = [math]::Round(($gpu | Measure-Object Power -Average).Average, 1)
    gpuMemMiB = ($gpu | Measure-Object Mem -Maximum).Maximum
}
$folder = Join-Path (Split-Path $PSScriptRoot) 'local/perf'
New-Item -ItemType Directory -Path $folder -Force | Out-Null
$safe = $Label -replace '[^a-zA-Z0-9_-]', '_'
$result | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $folder ((Get-Date -Format 'yyyyMMdd-HHmmss') + "-$safe.json")) -Encoding utf8
if (!$headsetLive) { Write-Warning "$Label is not a valid VR measurement: the headset is not streaming (poses=$($poseKeys.Count), $([math]::Round($mbit,1)) Mbit/s)." }
[PSCustomObject]$result
