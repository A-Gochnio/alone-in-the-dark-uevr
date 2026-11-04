# Shared helpers for the dev tools. Dot-source it: . (Join-Path $PSScriptRoot 'AitDCommon.ps1')
#
# Machine-specific settings go in the ignored local/machine.psd1, for example:
#   @{ GameDir = 'D:\Games\Steam\steamapps\common\AloneInTheDark'; WindowPosition = @(-2560, -434) }
# GameDir is optional: without it the Steam install of app 1310410 is found automatically.
# WindowPosition is optional: without it the game window stays where Windows puts it.

$script:AitDSteamAppId = 1310410

function Get-AitDMachineConfig {
    $file = Join-Path (Split-Path -Parent $PSScriptRoot) 'local\machine.psd1'
    if (Test-Path -LiteralPath $file) { return Import-PowerShellDataFile -LiteralPath $file }
    return @{}
}

function Get-AitDGameDir {
    $config = Get-AitDMachineConfig
    if ($env:AITD_GAME_DIR) { return $env:AITD_GAME_DIR }
    if ($config.GameDir) { return $config.GameDir }

    $steam = $null
    foreach ($key in 'HKCU:\Software\Valve\Steam', 'HKLM:\SOFTWARE\WOW6432Node\Valve\Steam', 'HKLM:\SOFTWARE\Valve\Steam') {
        $item = Get-ItemProperty -LiteralPath $key -ErrorAction SilentlyContinue
        if ($item.SteamPath) { $steam = $item.SteamPath; break }
        if ($item.InstallPath) { $steam = $item.InstallPath; break }
    }
    if (!$steam) { throw 'Steam not found. Set GameDir in local\machine.psd1 or $env:AITD_GAME_DIR.' }

    $libraries = @($steam)
    $vdf = Join-Path $steam 'steamapps\libraryfolders.vdf'
    if (Test-Path -LiteralPath $vdf) {
        foreach ($m in [regex]::Matches((Get-Content -Raw -LiteralPath $vdf), '"path"\s+"([^"]+)"')) {
            $libraries += $m.Groups[1].Value.Replace('\\', '\')
        }
    }
    foreach ($lib in ($libraries | Select-Object -Unique)) {
        $manifest = Join-Path $lib "steamapps\appmanifest_$script:AitDSteamAppId.acf"
        if (Test-Path -LiteralPath $manifest) {
            $dir = [regex]::Match((Get-Content -Raw -LiteralPath $manifest), '"installdir"\s+"([^"]+)"').Groups[1].Value
            return (Join-Path $lib "steamapps\common\$dir")
        }
    }
    throw "Alone in the Dark (Steam app $script:AitDSteamAppId) not found in any Steam library. Set GameDir in local\machine.psd1."
}

function Get-AitDGameBin { Join-Path (Get-AitDGameDir) 'AloneInTheDark\Binaries\Win64' }

function Get-AitDGameExe { Join-Path (Get-AitDGameBin) 'AloneInTheDark-Win64-Shipping.exe' }

# Moves a window to local\machine.psd1's WindowPosition, if one is set.
function Move-AitDGameWindow([IntPtr]$Handle) {
    $pos = (Get-AitDMachineConfig).WindowPosition
    if (!$pos) { return }
    if (!('AitD.Win' -as [type])) {
        Add-Type -Namespace AitD -Name Win -MemberDefinition '[DllImport("user32.dll")] public static extern bool SetWindowPos(System.IntPtr h, System.IntPtr a, int x, int y, int cx, int cy, uint f);'
    }
    [AitD.Win]::SetWindowPos($Handle, [IntPtr]::Zero, [int]$pos[0], [int]$pos[1], 0, 0, 0x15) | Out-Null
}
