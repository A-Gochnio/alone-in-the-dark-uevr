[CmdletBinding()]
param(
    # A clone of the public repository. Its files are replaced by this repo's last commit.
    [Parameter(Mandatory)] [string]$PublicClone,
    [string]$Message
)
# Copies the last commit of this (private) repo into a clone of the public repo and commits it there.
# Paths marked export-ignore in .gitattributes (agent notes, local/) are left out, and the copy is
# checked for personal paths and names before anything is committed. Push the public clone yourself.
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
if (!(Test-Path -LiteralPath (Join-Path $PublicClone '.git'))) { throw "$PublicClone is not a git clone." }

# Public commits should not carry a personal email address.
$email = (& git -C $PublicClone config user.email)
if ($email -notmatch 'users\.noreply\.github\.com$') {
    throw "The public clone commits as '$email'. Set a GitHub noreply address first: git -C `"$PublicClone`" config user.email <id>+<login>@users.noreply.github.com"
}

$commit = (& git -C $root rev-parse --short HEAD)
if (!$Message) { $Message = "Sync from private repo ($(Get-Date -Format yyyy-MM-dd))" }

# Replace everything except .git with the export.
Get-ChildItem -LiteralPath $PublicClone -Force | Where-Object Name -ne '.git' | Remove-Item -Recurse -Force
$zip = Join-Path ([IO.Path]::GetTempPath()) "aitd-public-$commit.zip"
& git -C $root archive --format=zip -o $zip HEAD
if ($LASTEXITCODE -ne 0) { throw 'git archive failed.' }
Add-Type -AssemblyName System.IO.Compression.FileSystem
[IO.Compression.ZipFile]::ExtractToDirectory($zip, $PublicClone)
Remove-Item -LiteralPath $zip

# Generic patterns, plus your own PrivateWords (user name, PC name...) from the ignored local/machine.psd1.
. (Join-Path $PSScriptRoot 'AitDCommon.ps1')
$words = @('C:\\Users\\', '/User[s]/', '@gmail\.', 'Steam[L]ibrary') + @((Get-AitDMachineConfig).PrivateWords | Where-Object { $_ } | ForEach-Object { [regex]::Escape($_) })
$forbidden = $words -join '|'
$hits = Get-ChildItem -LiteralPath $PublicClone -Recurse -File | Where-Object FullName -notmatch '\\\.git\\' |
    Select-String -Pattern $forbidden
if ($hits) {
    $hits | ForEach-Object { Write-Host "$($_.Path):$($_.LineNumber): $($_.Line.Trim())" -ForegroundColor Red }
    throw 'Private details found in the export; nothing was committed. Fix them in the private repo and rerun.'
}

& git -C $PublicClone add -A
& git -C $PublicClone commit -m $Message
Write-Host "Committed in $PublicClone. Review it, then: git -C `"$PublicClone`" push" -ForegroundColor Green
