param(
    [Parameter(Mandatory)][string[]]$Assignment,  # e.g. 'VR_RenderingMethod=0','OpenXR_ResolutionScale=0.850000'
    [switch]$Force                                # allow editing while the game runs (UEVR may overwrite it on save)
)
# Edits keys in the live UEVR profile config.txt after backing it up. Only existing keys are changed.
# OpenXR_ResolutionScale only takes effect when UEVR creates its OpenXR session, i.e. on the next injection.
$ErrorActionPreference = 'Stop'
$cfg = Join-Path $env:APPDATA 'UnrealVRMod\AloneInTheDark-Win64-Shipping\config.txt'
if (!$Force -and (Get-Process AloneInTheDark-Win64-Shipping -ErrorAction SilentlyContinue)) {
    throw 'Stop the game first (or pass -Force); UEVR rewrites config.txt when it saves.'
}
$backup = Join-Path (Split-Path $PSScriptRoot) ('backups/uevr-config-' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
New-Item -ItemType Directory -Path $backup -Force | Out-Null
Copy-Item -LiteralPath $cfg -Destination $backup
$lines = Get-Content -LiteralPath $cfg
foreach ($item in $Assignment) {
    $key, $value = $item -split '=', 2
    $index = [Array]::FindIndex($lines, [Predicate[string]]{ param($l) $l -like "$key=*" })
    if ($index -lt 0) { throw "Key '$key' is not present in config.txt." }
    [PSCustomObject]@{ Key = $key; Before = ($lines[$index] -split '=', 2)[1]; After = $value }
    $lines[$index] = "$key=$value"
}
Set-Content -LiteralPath $cfg -Value $lines -Encoding ascii
Write-Host "Backup: $backup"
