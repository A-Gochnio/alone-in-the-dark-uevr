[CmdletBinding()]
param(
    # Release version. Default: release/VERSION. A new value is written back to release/VERSION.
    [string]$Version,
    # The UEVR build players must use (a tag of github.com/praydog/UEVR-nightly).
    [string]$UevrTag = 'nightly-01143-4ee5c6b6162dee2291fc75f9dfc57667f6d45a2d',
    [string]$OutDir,
    # Package the working tree instead of the last commit (test builds only).
    [switch]$WorkingTree,
    # Build even if config.txt or uobjecthook/ in the live UEVR profile differ from the package.
    [switch]$IgnoreLiveDiff
)

# Builds the player release from the last commit (never from the live profile or uncommitted edits):
#   dist/AloneInTheDark-VR-v<version>.zip
#     AloneInTheDark-Win64-Shipping.zip   UEVR profile, for UEVRInjector's "Import Config"
#     README.txt                          install, controls, settings (release/README.md)
#     Engine-ini-additions.txt            recommended CVars (release/Engine-ini-additions.txt)
#     Install.bat, Install.ps1            installer: profile + Engine.ini, with backups
# Only the play files are packaged: config.txt, cvars_data.txt, uobjecthook/*.json and the scripts
# Restart-AitDVR.ps1 deploys (alone_in_the_dark_vr.lua, aitd_vr*.lua). Debug scripts, plugins
# (uevr_mcp.dll), tune files, logs, saves and OptiScaler/AFW files are never included.

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.IO.Compression, System.IO.Compression.FileSystem

$root = Split-Path -Parent $PSScriptRoot
$versionFile = Join-Path $root 'release\VERSION'
if (!$OutDir) { $OutDir = Join-Path $root 'dist' }
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

if ($Version) {
    if ($Version -notmatch '^\d+\.\d+\.\d+([-.][0-9A-Za-z.]+)?$') { throw "Version must look like 1.2.3 or 1.2.3-beta: $Version" }
    [IO.File]::WriteAllText($versionFile, "$Version`n")
    Write-Warning "release/VERSION is now $Version; commit it."
} else {
    $Version = ([IO.File]::ReadAllText($versionFile)).Trim()
}
$uevrBuild = if ($UevrTag -match '^nightly-(\d+)-([0-9a-f]{8})') { "$($Matches[1]) ($($Matches[2]))" } else { $UevrTag }

# Source tree: profile/ and release/ as of HEAD, so work in progress in the clone never ships.
$commit = (& git -C $root rev-parse --short HEAD)
if ($LASTEXITCODE -ne 0) { throw 'git rev-parse failed; run from a git clone or pass -WorkingTree.' }
if ($WorkingTree) {
    $src = $root
    $commit = "$commit+working-tree"
} else {
    $src = Join-Path $OutDir '.source'
    if (Test-Path -LiteralPath $src) { Remove-Item -LiteralPath $src -Recurse -Force }
    $archive = Join-Path $OutDir '.source.zip'
    & git -C $root archive --format=zip -o $archive HEAD profile release
    if ($LASTEXITCODE -ne 0) { throw 'git archive failed.' }
    [IO.Compression.ZipFile]::ExtractToDirectory($archive, $src)
    Remove-Item -LiteralPath $archive
    $uncommitted = (& git -C $root status --porcelain -- profile release)
    if ($uncommitted) {
        Write-Warning ("Uncommitted changes are NOT packaged (commit them first, or use -WorkingTree for a test build):`n" + (($uncommitted | ForEach-Object { "  $_" }) -join "`n"))
    }
}
$profileDir = Join-Path $src 'profile'
$releaseDir = Join-Path $src 'release'

# Profile files, as paths relative to profile/ (= paths inside the UEVR profile zip).
$files = @('config.txt', 'cvars_data.txt')
$files += Get-ChildItem (Join-Path $profileDir 'uobjecthook') -Filter '*.json' | ForEach-Object { "uobjecthook/$($_.Name)" }
$files += 'scripts/alone_in_the_dark_vr.lua'
$files += Get-ChildItem (Join-Path $profileDir 'scripts') -Filter 'aitd_vr*.lua' | Sort-Object Name | ForEach-Object { "scripts/$($_.Name)" }
foreach ($f in $files) {
    if (!(Test-Path -LiteralPath (Join-Path $profileDir $f))) { throw "Missing profile file: profile/$f" }
}
if (!($files -contains 'uobjecthook/camera_state.json')) { throw 'profile/uobjecthook/camera_state.json is missing (first-person camera).' }

# Sanity checks: the release config must be the play setup, and nothing machine-specific may leak.
$config = [IO.File]::ReadAllText((Join-Path $profileDir 'config.txt'))
$required = @{
    'Frontend_RequestedRuntime' = 'openxr_loader.dll'
    'FrameworkConfig_MenuOpen' = 'false'
    'UObjectHook_EnabledAtStartup' = 'true'
    'VR_RenderingMethod' = '0'
    'VR_ControllersAllowed' = 'true'
}
foreach ($key in $required.Keys) {
    $m = [regex]::Match($config, "(?m)^$([regex]::Escape($key))=(.*?)\r?$")
    if (!$m.Success -or $m.Groups[1].Value -ne $required[$key]) {
        throw "profile/config.txt: $key should be $($required[$key]) for a release (found '$($m.Groups[1].Value)')."
    }
}
$forbidden = 'C:\\Users|127\.0\.0\.1|8899|uevr_mcp|OptiScaler|AFW|AITD_SIM'
foreach ($f in $files) {
    $text = [IO.File]::ReadAllText((Join-Path $profileDir $f))
    $hit = [regex]::Match($text, $forbidden, 'IgnoreCase')
    if ($hit.Success) { throw "profile/$f contains '$($hit.Value)', which is dev-only or machine-specific." }
}

# Compare with the profile actually played on this PC. Settings changed in the UEVR menu land only
# there, so a config/UObjectHook difference stops the build; script differences are only reported,
# since scripts are always deployed from the repository.
$live = Join-Path $env:APPDATA 'UnrealVRMod\AloneInTheDark-Win64-Shipping'
if ($env:APPDATA -and (Test-Path -LiteralPath $live)) {
    $settingsDrift = @()
    $scriptDrift = @()
    foreach ($f in $files) {
        $livePath = Join-Path $live $f
        $isScript = $f -like 'scripts/*'
        if (!(Test-Path -LiteralPath $livePath)) {
            if ($isScript) { $scriptDrift += "$f (missing in the live profile)" } else { $settingsDrift += "$f (missing in the live profile)" }
            continue
        }
        $a = ([IO.File]::ReadAllText($livePath)) -replace "`r`n", "`n"
        $b = ([IO.File]::ReadAllText((Join-Path $profileDir $f))) -replace "`r`n", "`n"
        if ($a -ne $b) { if ($isScript) { $scriptDrift += $f } else { $settingsDrift += $f } }
    }
    foreach ($s in Get-ChildItem (Join-Path $live 'scripts') -Filter '*.lua' -ErrorAction SilentlyContinue) {
        if (!($files -contains "scripts/$($s.Name)")) { $scriptDrift += "scripts/$($s.Name) (live only, not packaged)" }
    }
    foreach ($u in Get-ChildItem (Join-Path $live 'uobjecthook') -Filter '*.json' -ErrorAction SilentlyContinue) {
        if (!($files -contains "uobjecthook/$($u.Name)")) { $settingsDrift += "uobjecthook/$($u.Name) (live only)" }
    }
    if ($scriptDrift.Count -gt 0) {
        Write-Warning ("Live scripts differ from the package (the package uses the repository's):`n" + (($scriptDrift | ForEach-Object { "  $_" }) -join "`n"))
    }
    if ($settingsDrift.Count -gt 0) {
        $list = ($settingsDrift | ForEach-Object { "  $_" }) -join "`n"
        if (!$IgnoreLiveDiff) {
            throw "Live UEVR settings differ from profile/ in the package:`n$list`nCopy the changes you want into profile/ and commit them, or rerun with -IgnoreLiveDiff."
        }
        Write-Warning "Live UEVR settings differ (packaging the repository copy):`n$list"
    }
}

function New-Zip {
    param([string]$Path, [object[]]$Entries)  # each entry: @{ Name = 'a/b.txt'; Source = 'C:\...' }
    if (Test-Path -LiteralPath $Path) { Remove-Item -LiteralPath $Path }
    $zip = [IO.Compression.ZipFile]::Open($Path, 'Create')
    try {
        foreach ($e in $Entries) {
            # Forward slashes: Windows PowerShell's Compress-Archive writes backslashes, which other unzip tools mangle.
            [void][IO.Compression.ZipFileExtensions]::CreateEntryFromFile($zip, $e.Source, $e.Name, 'Optimal')
        }
    } finally {
        $zip.Dispose()
    }
}

$name = "AloneInTheDark-VR-v$Version"
$stage = Join-Path $OutDir $name
if (Test-Path -LiteralPath $stage) { Remove-Item -LiteralPath $stage -Recurse -Force }
New-Item -ItemType Directory -Force -Path $stage | Out-Null

# UEVR names the imported profile after the zip, so this name must match the game executable.
$profileZip = Join-Path $stage 'AloneInTheDark-Win64-Shipping.zip'
New-Zip -Path $profileZip -Entries @($files | ForEach-Object { @{ Name = $_; Source = (Join-Path $profileDir $_) } })

$readme = [IO.File]::ReadAllText((Join-Path $releaseDir 'README.md'))
$readme = $readme.Replace('{{VERSION}}', $Version).Replace('{{UEVR_TAG}}', $UevrTag).Replace('{{UEVR_BUILD}}', $uevrBuild)
if ($readme -match '\{\{\w+\}\}') { throw "release/README.md has an unknown placeholder: $($Matches[0])" }
$crlf = { param($t) ($t -replace "`r`n", "`n") -replace "`n", "`r`n" }
[IO.File]::WriteAllText((Join-Path $stage 'README.txt'), (& $crlf $readme))
foreach ($f in @('Engine-ini-additions.txt', 'Install.ps1', 'Install.bat')) {
    [IO.File]::WriteAllText((Join-Path $stage $f), (& $crlf ([IO.File]::ReadAllText((Join-Path $releaseDir $f)))))
}

# The Discord post text sits next to the zip, not in it.
$post = [IO.File]::ReadAllText((Join-Path $releaseDir 'DISCORD_POST.md')).Replace('{{VERSION}}', $Version)
[IO.File]::WriteAllText((Join-Path $OutDir "$name-discord-post.txt"), $post)

$releaseZip = Join-Path $OutDir "$name.zip"
New-Zip -Path $releaseZip -Entries @(
    @{ Name = 'AloneInTheDark-Win64-Shipping.zip'; Source = $profileZip },
    @{ Name = 'README.txt'; Source = (Join-Path $stage 'README.txt') },
    @{ Name = 'Engine-ini-additions.txt'; Source = (Join-Path $stage 'Engine-ini-additions.txt') },
    @{ Name = 'Install.bat'; Source = (Join-Path $stage 'Install.bat') },
    @{ Name = 'Install.ps1'; Source = (Join-Path $stage 'Install.ps1') }
)

if (!$WorkingTree) { Remove-Item -LiteralPath $src -Recurse -Force }

Write-Host "Packaged $($files.Count) profile files:"
$files | ForEach-Object { Write-Host "  $_" }
Write-Host ''
Write-Host "Release: $releaseZip"
Write-Host "  version $Version, UEVR $UevrTag, commit $commit"
Write-Host "  Discord post text: $(Join-Path $OutDir "$name-discord-post.txt")"
Write-Host "  $([math]::Round((Get-Item $releaseZip).Length / 1KB, 1)) KB, SHA-256 $((Get-FileHash $releaseZip -Algorithm SHA256).Hash)"
