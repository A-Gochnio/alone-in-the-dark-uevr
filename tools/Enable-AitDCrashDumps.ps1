<#
.SYNOPSIS
Turns Windows Error Reporting full local dumps on (or off) for the game. Run as administrator.

.DESCRIPTION
The game's most common crash is a Control Flow Guard fastfail that bypasses Unreal's crash handler,
so no UE crash folder is written. With LocalDumps, Windows keeps a full dump of the next one in
local/crash-dumps (ignored by git, like all of local/).

.EXAMPLE
./tools/Enable-AitDCrashDumps.ps1
./tools/Enable-AitDCrashDumps.ps1 -Remove
#>
param([switch]$Remove)
$ErrorActionPreference = 'Stop'
$key = 'HKLM:\SOFTWARE\Microsoft\Windows\Windows Error Reporting\LocalDumps\AloneInTheDark-Win64-Shipping.exe'
if ($Remove) {
    Remove-Item $key -ErrorAction SilentlyContinue
    'LocalDumps removed.'
    return
}
$folder = Join-Path (Split-Path -Parent $PSScriptRoot) 'local\crash-dumps'
New-Item -ItemType Directory -Force $folder | Out-Null
New-Item -Path $key -Force | Out-Null
New-ItemProperty -Path $key -Name DumpFolder -PropertyType ExpandString -Value $folder -Force | Out-Null
New-ItemProperty -Path $key -Name DumpType -PropertyType DWord -Value 2 -Force | Out-Null
New-ItemProperty -Path $key -Name DumpCount -PropertyType DWord -Value 5 -Force | Out-Null
Get-ItemProperty $key | Select-Object DumpFolder, DumpType, DumpCount
