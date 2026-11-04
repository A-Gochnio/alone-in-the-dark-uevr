[CmdletBinding()]
param(
    [ValidateSet('Install','Remove','Status')]
    [string]$Mode = 'Status'
)

$ErrorActionPreference = 'Stop'
$gameProcess = 'AloneInTheDark-Win64-Shipping'
. (Join-Path $PSScriptRoot 'AitDCommon.ps1')
$gameBin = Get-AitDGameBin
$stage = Join-Path $PSScriptRoot '..\local\tools\OptiScaler-v0.9.4-staged'
$stateFile = Join-Path $PSScriptRoot '..\local\optiscaler-install.json'
$expectedArchiveHash = '575cb4df866116093df75af607e37fd70e10f5163e0f23fd5c804142e80ef0ad'

$rootFiles = @(
    'amd_fidelityfx_dx12.dll',
    'amd_fidelityfx_framegeneration_dx12.dll',
    'amd_fidelityfx_upscaler_dx12.dll',
    'amd_fidelityfx_vk.dll',
    'dlssg_to_fsr3_amd_is_better.dll',
    'fakenvapi.dll',
    'fakenvapi.ini',
    'libxell.dll',
    'libxess_dx11.dll',
    'libxess_fg.dll',
    'libxess.dll',
    'OptiScaler.ini'
)

function Assert-GameStopped {
    if (Get-Process -Name $gameProcess -ErrorAction SilentlyContinue) {
        throw 'Close Alone in the Dark before installing or removing OptiScaler.'
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
        ProxyOriginalFilename = if (Test-Path -LiteralPath $proxy) { (Get-Item -LiteralPath $proxy).VersionInfo.OriginalFilename } else { $null }
        StateFile = $stateFile
        StageDirectory = $stage
    }
}

if ($Mode -eq 'Status') {
    Get-Status
    exit 0
}

Assert-GameStopped

if ($Mode -eq 'Install') {
    if (Test-Path -LiteralPath $stateFile) {
        throw "Install state already exists: $stateFile"
    }
    if (!(Test-Path -LiteralPath (Join-Path $stage 'OptiScaler.dll'))) {
        throw "Staged OptiScaler release is missing: $stage"
    }
    foreach ($folder in @('D3D12_Optiscaler','Licenses')) {
        if (Test-Path -LiteralPath (Join-Path $gameBin $folder)) {
            throw "Destination folder already exists; inspect it before installation: $folder"
        }
    }

    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $backup = Join-Path $PSScriptRoot "..\backups\$stamp-before-optiscaler"
    New-Item -ItemType Directory -Path $backup -Force | Out-Null
    $configuredIni = Join-Path $backup 'OptiScaler.ini.configured'
    Copy-Item -LiteralPath (Join-Path $stage 'OptiScaler.ini') -Destination $configuredIni
    Set-IniValue $configuredIni 'Upscalers' 'Dx12Upscaler' 'dlss'
    Set-IniValue $configuredIni 'FrameGen' 'Enabled' 'false'
    Set-IniValue $configuredIni 'FrameGen' 'FGInput' 'upscaler'
    Set-IniValue $configuredIni 'FrameGen' 'FGOutput' 'fsrfg'
    Set-IniValue $configuredIni 'OptiFG' 'HUDFix' 'true'
    Set-IniValue $configuredIni 'OptiFG' 'HUDLimit' '1'
    Set-IniValue $configuredIni 'Menu' 'ShortcutKey' '0x24'
    Set-IniValue $configuredIni 'Hotfix' 'DisableOverlays' 'false'
    Set-IniValue $configuredIni 'Log' 'LogToFile' 'true'

    $destinations = @($rootFiles | ForEach-Object { $_ }) + @('dxgi.dll')
    $preexisting = @()
    foreach ($relative in $destinations) {
        $target = Join-Path $gameBin $relative
        if (Test-Path -LiteralPath $target) {
            Copy-Item -LiteralPath $target -Destination (Join-Path $backup $relative) -Force
            $preexisting += $relative
        }
    }

    foreach ($relative in $rootFiles | Where-Object { $_ -ne 'OptiScaler.ini' }) {
        Copy-Item -LiteralPath (Join-Path $stage $relative) -Destination (Join-Path $gameBin $relative) -Force
    }
    Copy-Item -LiteralPath $configuredIni -Destination (Join-Path $gameBin 'OptiScaler.ini') -Force
    Copy-Item -LiteralPath (Join-Path $stage 'OptiScaler.dll') -Destination (Join-Path $gameBin 'dxgi.dll') -Force
    Copy-Item -LiteralPath (Join-Path $stage 'D3D12_Optiscaler') -Destination $gameBin -Recurse -Force
    Copy-Item -LiteralPath (Join-Path $stage 'Licenses') -Destination $gameBin -Recurse -Force

    $installed = @()
    foreach ($relative in $destinations) {
        $target = Join-Path $gameBin $relative
        $installed += [PSCustomObject]@{RelativePath=$relative;SHA256=(Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash}
    }
    foreach ($folder in @('D3D12_Optiscaler','Licenses')) {
        Get-ChildItem -LiteralPath (Join-Path $gameBin $folder) -File -Recurse | ForEach-Object {
            $relative = $_.FullName.Substring($gameBin.Length + 1)
            $installed += [PSCustomObject]@{RelativePath=$relative;SHA256=(Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash}
        }
    }
    [PSCustomObject]@{
        Version='0.9.4'
        ReleaseUrl='https://github.com/optiscaler/OptiScaler/releases/tag/v0.9.4'
        ArchiveSHA256=$expectedArchiveHash
        InstalledAt=(Get-Date).ToString('o')
        GameBin=$gameBin
        Backup=$backup
        Preexisting=$preexisting
        Files=$installed
    } | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $stateFile -Encoding utf8

    Get-Status
    exit 0
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
foreach ($folder in @('D3D12_Optiscaler','Licenses')) {
    $path = Join-Path $gameBin $folder
    if ((Test-Path -LiteralPath $path) -and !(Get-ChildItem -LiteralPath $path -Force)) {
        Remove-Item -LiteralPath $path -Force
    }
}
Remove-Item -LiteralPath $stateFile -Force
Get-Status
