[CmdletBinding()]
param(
    [ValidateSet('Apply', 'Status', 'Restore')]
    [string]$Mode = 'Apply',
    [string]$BackupDirectory,
    [switch]$Force,
    # Extra or replacement menu keys, e.g. @{ DLSSQualityLevel = '-1'; 'sg.ShadowQuality' = '0' }.
    [hashtable]$Override = @{},
    # CVars written as the [SystemSettings] section of Engine.ini (replacing any existing one); for
    # settings the menu does not expose, e.g. @{ 'r.ContactShadows' = '0' }.
    [hashtable]$SystemSettings = @{}
)

$ErrorActionPreference = 'Stop'

$gameProcessName = 'AloneInTheDark-Win64-Shipping'
$savedRoot = Join-Path $env:LOCALAPPDATA 'AloneInTheDark\Saved'
$gameUserSettings = Join-Path $savedRoot 'Config\WindowsNoEditor\GameUserSettings.ini'
$settingsSave = Join-Path $savedRoot 'SaveGames\settings.sav'
$engineIni = Join-Path $savedRoot 'Config\WindowsNoEditor\Engine.ini'
$repoRoot = Split-Path -Parent $PSScriptRoot
$backupRoot = Join-Path $repoRoot 'backups'

$desired = [ordered]@{
    'sg.TextureQuality' = '3'
    'sg.AnisotropicFilteringQuality' = '3'
    'DLSSQualityLevel' = '2'
    'PostEffectExtra' = 'Off'
    'MotionBlurQuality' = 'Off'
    'DepthOfFieldEnabled' = 'False'
    'ChromaticAberrationEnabled' = 'False'
}
foreach ($key in $Override.Keys) { $desired[$key] = [string]$Override[$key] }

function Get-IniValue {
    param([string]$Text, [string]$Key)

    $match = [regex]::Match($Text, "(?m)^$([regex]::Escape($Key))=(.*)$")
    if (!$match.Success) {
        return $null
    }
    return $match.Groups[1].Value.TrimEnd("`r")
}

function Set-IniValue {
    param([string]$Text, [string]$Key, [string]$Value)

    $pattern = "(?m)^$([regex]::Escape($Key))=.*$"
    if (![regex]::IsMatch($Text, $pattern)) {
        throw "Required setting '$Key' was not found. Refusing to append it outside its original section."
    }
    return [regex]::Replace($Text, $pattern, "$Key=$Value", 1)
}

foreach ($path in @($gameUserSettings, $settingsSave)) {
    if (!(Test-Path -LiteralPath $path)) {
        throw "Required settings file is missing: $path"
    }
}

if ($Mode -eq 'Status') {
    foreach ($path in @($gameUserSettings, $settingsSave)) {
        $text = [IO.File]::ReadAllText($path)
        foreach ($entry in $desired.GetEnumerator()) {
            [PSCustomObject]@{
                File = $path
                Key = $entry.Key
                Current = Get-IniValue -Text $text -Key $entry.Key
                Desired = $entry.Value
            }
        }
    }
    return
}

$game = Get-Process -Name $gameProcessName -ErrorAction SilentlyContinue | Select-Object -First 1
if ($game -and !$Force) {
    throw "The game is running (PID $($game.Id)). Stop it before changing persistent graphics settings, or pass -Force if you accept that the game may overwrite them."
}

if ($Mode -eq 'Restore') {
    if ([string]::IsNullOrWhiteSpace($BackupDirectory)) {
        throw 'Restore requires -BackupDirectory.'
    }

    $resolvedBackup = (Resolve-Path -LiteralPath $BackupDirectory).Path
    foreach ($name in @('GameUserSettings.ini', 'settings.sav')) {
        $source = Join-Path $resolvedBackup $name
        if (!(Test-Path -LiteralPath $source)) {
            throw "Backup file is missing: $source"
        }
    }

    Copy-Item -LiteralPath (Join-Path $resolvedBackup 'GameUserSettings.ini') -Destination $gameUserSettings -Force
    Copy-Item -LiteralPath (Join-Path $resolvedBackup 'settings.sav') -Destination $settingsSave -Force
    if (Test-Path -LiteralPath (Join-Path $resolvedBackup 'Engine.ini')) {
        Copy-Item -LiteralPath (Join-Path $resolvedBackup 'Engine.ini') -Destination $engineIni -Force
    }
    Write-Host "Restored graphics settings from $resolvedBackup"
    return
}

$texts = @{}
$needsChange = $false
foreach ($path in @($gameUserSettings, $settingsSave)) {
    $text = [IO.File]::ReadAllText($path)
    $texts[$path] = $text
    foreach ($entry in $desired.GetEnumerator()) {
        if ((Get-IniValue -Text $text -Key $entry.Key) -ne $entry.Value) {
            $needsChange = $true
        }
    }
}

if ($SystemSettings.Count -gt 0) { $needsChange = $true }
if (!$needsChange) {
    Write-Host 'VR graphics candidate is already applied to both settings files.'
    return
}

$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$createdBackup = Join-Path $backupRoot "graphics-$stamp"
New-Item -ItemType Directory -Force -Path $createdBackup | Out-Null
Copy-Item -LiteralPath $gameUserSettings -Destination (Join-Path $createdBackup 'GameUserSettings.ini')
Copy-Item -LiteralPath $settingsSave -Destination (Join-Path $createdBackup 'settings.sav')
if (Test-Path -LiteralPath $engineIni) { Copy-Item -LiteralPath $engineIni -Destination (Join-Path $createdBackup 'Engine.ini') }

if ($SystemSettings.Count -gt 0) {
    $engine = if (Test-Path -LiteralPath $engineIni) { [IO.File]::ReadAllText($engineIni) } else { '' }
    $engine = [regex]::Replace($engine, '(?ms)^\[SystemSettings\]\r?\n.*?(?=^\[|\z)', '').TrimEnd()
    $lines = @('', '', '[SystemSettings]') + @($SystemSettings.Keys | Sort-Object | ForEach-Object { "$_=$($SystemSettings[$_])" })
    [IO.File]::WriteAllText($engineIni, $engine + ($lines -join "`r`n") + "`r`n", [Text.UTF8Encoding]::new($false))
}

foreach ($path in @($gameUserSettings, $settingsSave)) {
    $text = $texts[$path]
    foreach ($entry in $desired.GetEnumerator()) {
        $text = Set-IniValue -Text $text -Key $entry.Key -Value $entry.Value
    }
    [IO.File]::WriteAllText($path, $text, [Text.UTF8Encoding]::new($false))
}

Write-Host "Applied the VR graphics candidate. Backup: $createdBackup"
& $PSCommandPath -Mode Status
