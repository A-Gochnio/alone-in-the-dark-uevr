[CmdletBinding()]
param(
    [ValidateSet('Install', 'Remove', 'Status')]
    [string]$Mode = 'Status'
)

$ErrorActionPreference = 'Stop'

$gameProcess = 'AloneInTheDark-Win64-Shipping'
. (Join-Path $PSScriptRoot 'AitDCommon.ps1')
$gameBin = Get-AitDGameBin
$stage = Join-Path $PSScriptRoot '..\local\tools\witcher3vr-v0.9.8v2\extracted\bin\x64_dx12'
$stateFile = Join-Path $PSScriptRoot '..\local\stereo-optiscaler-install.json'
$releaseUrl = 'https://github.com/tig3rmast3r/witcher3-vr/releases/tag/v0.9.8v2'
$archiveHash = 'A59F96F43DB9C9509D0EE07638A7F5D1EDD280010A836105B6E93F820B31BD5A'

$payload = [ordered]@{
    'dxgi.dll' = 'witcher3vr-optiscaler-dlss5-reference\OptiScaler.dll'
    'nvngx.dll_dlssnr.dll' = 'witcher3vr-optiscaler-dlss5-reference\nvngx.dll_dlssnr.dll'
    'amd_fidelityfx_framegeneration_dx12.dll' = 'witcher3vr-optiscaler-dlss5-reference\amd_fidelityfx_framegeneration_dx12.dll'
    'ofxr_amd_fidelityfx_framegeneration_dx12.dll' = 'witcher3vr-optiscaler-dlss5-reference\ofxr_amd_fidelityfx_framegeneration_dx12.dll'
    'XR_APILAYER_XRFrameBridge_diagnostic.dll' = 'XR_APILAYER_XRFrameBridge_diagnostic.dll'
    'XR_APILAYER_XRFrameBridge_diagnostic.json' = 'XR_APILAYER_XRFrameBridge_diagnostic.json'
}

$expectedHashes = @{
    'dxgi.dll' = 'D244828FC9742801B2184C04847097EB1D2BB6656F084BED0EC8DA86E7AADEAA'
    'nvngx.dll_dlssnr.dll' = '840187D05138C90069287BB1796AAB870C8FCF4F4DBE96EA5A907EFA32C74B4C'
    'amd_fidelityfx_framegeneration_dx12.dll' = '02297BEEDD285E822D3A64F314CF00FAF378DCEC0EDC47FF0C4DD71B3A8C2F18'
    'ofxr_amd_fidelityfx_framegeneration_dx12.dll' = '02297BEEDD285E822D3A64F314CF00FAF378DCEC0EDC47FF0C4DD71B3A8C2F18'
    'XR_APILAYER_XRFrameBridge_diagnostic.dll' = 'CE27A143568038A38778A9297582B70132FFE27D800E405A5F037E10ADDFBE9B'
    'XR_APILAYER_XRFrameBridge_diagnostic.json' = '6DB89108FD6073EBF9E85F9B7D7822B348E066736182367BA4EC767032D840EE'
}

function Assert-GameStopped {
    if (Get-Process -Name $gameProcess -ErrorAction SilentlyContinue) {
        throw 'Close Alone in the Dark before installing or removing the stereo OptiScaler experiment.'
    }
}

function Set-IniValue {
    param([string]$Path, [string]$Section, [string]$Key, [string]$Value)

    $lines = [Collections.Generic.List[string]](Get-Content -LiteralPath $Path)
    $inSection = $false
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match '^\s*\[(.+)\]\s*$') {
            $inSection = $Matches[1] -eq $Section
            continue
        }
        if ($inSection -and $lines[$i] -match ('^\s*' + [Regex]::Escape($Key) + '\s*=')) {
            $lines[$i] = "$Key=$Value"
            Set-Content -LiteralPath $Path -Value $lines -Encoding utf8
            return
        }
    }
    throw "Could not find [$Section] $Key in $Path"
}

function Get-Status {
    $proxy = Join-Path $gameBin 'dxgi.dll'
    [PSCustomObject]@{
        Installed = (Test-Path -LiteralPath $stateFile) -and (Test-Path -LiteralPath $proxy)
        ProxyPath = $proxy
        ProxySHA256 = if (Test-Path -LiteralPath $proxy) { (Get-FileHash -Algorithm SHA256 -LiteralPath $proxy).Hash } else { $null }
        OpenXRLayer = Join-Path $gameBin 'XR_APILAYER_XRFrameBridge_diagnostic.json'
        StateFile = $stateFile
        StageDirectory = $stage
    }
}

if ($Mode -eq 'Status') {
    Get-Status
    return
}

Assert-GameStopped

if ($Mode -eq 'Install') {
    if (Test-Path -LiteralPath $stateFile) {
        throw "Stereo experiment state already exists: $stateFile"
    }

    foreach ($entry in $payload.GetEnumerator()) {
        $source = Join-Path $stage $entry.Value
        if (!(Test-Path -LiteralPath $source)) {
            throw "Staged payload file is missing: $source"
        }
        $actual = (Get-FileHash -Algorithm SHA256 -LiteralPath $source).Hash
        if ($actual -ne $expectedHashes[$entry.Key]) {
            throw "Hash mismatch for $source. Expected $($expectedHashes[$entry.Key]), got $actual."
        }
    }

    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $backup = Join-Path $PSScriptRoot "..\backups\$stamp-before-stereo-optiscaler"
    New-Item -ItemType Directory -Force -Path $backup | Out-Null

    $configuredOpti = Join-Path $backup 'OptiScaler.ini.configured'
    Copy-Item -LiteralPath (Join-Path $stage 'OptiScaler.ini') -Destination $configuredOpti
    Set-IniValue $configuredOpti 'Upscalers' 'Dx12Upscaler' 'dlss'
    Set-IniValue $configuredOpti 'FrameGen' 'Enabled' 'false'
    Set-IniValue $configuredOpti 'Menu' 'ShortcutKey' '0x24'
    Set-IniValue $configuredOpti 'Log' 'LogToFile' 'true'
    Set-IniValue $configuredOpti 'Hotfix' 'DisableOverlays' 'false'

    $configuredBridge = Join-Path $backup 'optiscaler_bridge.ini.configured'
    Copy-Item -LiteralPath (Join-Path $stage 'optiscaler_bridge.ini') -Destination $configuredBridge
    Set-IniValue $configuredBridge 'optiscaler' 'enabled' '1'

    $configuredOfxr = Join-Path $backup 'ofxr_bridge.ini.configured'
    Copy-Item -LiteralPath (Join-Path $stage 'ofxr_bridge.ini') -Destination $configuredOfxr
    Set-IniValue $configuredOfxr 'ofxr' 'enabled' '1'
    Set-IniValue $configuredOfxr 'ofxr' 'frame_generation' 'fsr3'
    Set-IniValue $configuredOfxr 'diagnostics' 'logging_enabled' '1'
    Set-IniValue $configuredOfxr 'diagnostics' 'cadence_logging_enabled' '1'

    $destinations = @($payload.Keys) + @('OptiScaler.ini', 'optiscaler_bridge.ini', 'ofxr_bridge.ini')
    $preexisting = @()
    foreach ($relative in $destinations) {
        $target = Join-Path $gameBin $relative
        if (Test-Path -LiteralPath $target) {
            Copy-Item -LiteralPath $target -Destination (Join-Path $backup $relative) -Force
            $preexisting += $relative
        }
    }

    foreach ($entry in $payload.GetEnumerator()) {
        Copy-Item -LiteralPath (Join-Path $stage $entry.Value) -Destination (Join-Path $gameBin $entry.Key) -Force
    }
    Copy-Item -LiteralPath $configuredOpti -Destination (Join-Path $gameBin 'OptiScaler.ini') -Force
    Copy-Item -LiteralPath $configuredBridge -Destination (Join-Path $gameBin 'optiscaler_bridge.ini') -Force
    Copy-Item -LiteralPath $configuredOfxr -Destination (Join-Path $gameBin 'ofxr_bridge.ini') -Force

    $installed = foreach ($relative in $destinations) {
        $target = Join-Path $gameBin $relative
        [PSCustomObject]@{
            RelativePath = $relative
            SHA256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $target).Hash
        }
    }

    [PSCustomObject]@{
        Version = 'Witcher3VR v0.9.8v2 / OptiScaler V23244 / OFXR v0.2.1'
        ReleaseUrl = $releaseUrl
        ArchiveSHA256 = $archiveHash
        SourceCommit = '0b4abc0808ac49679e73674d6d0ecc59303e0242'
        InstalledAt = (Get-Date).ToString('o')
        GameBin = $gameBin
        Backup = $backup
        Preexisting = $preexisting
        Files = $installed
    } | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $stateFile -Encoding utf8

    Get-Status
    return
}

if (!(Test-Path -LiteralPath $stateFile)) {
    throw "Stereo experiment state is missing: $stateFile"
}

$state = Get-Content -LiteralPath $stateFile -Raw | ConvertFrom-Json
$expectedRoot = [IO.Path]::GetFullPath($gameBin).TrimEnd('\') + '\'
foreach ($entry in $state.Files) {
    $target = [IO.Path]::GetFullPath((Join-Path $gameBin $entry.RelativePath))
    if (!$target.StartsWith($expectedRoot, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing to remove path outside game directory: $target"
    }
    if (Test-Path -LiteralPath $target) {
        Remove-Item -LiteralPath $target -Force
    }
}
foreach ($relative in $state.Preexisting) {
    Copy-Item -LiteralPath (Join-Path $state.Backup $relative) -Destination (Join-Path $gameBin $relative) -Force
}
Remove-Item -LiteralPath $stateFile -Force
Get-Status
