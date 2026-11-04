param(
    [Parameter(Mandatory)][string[]]$Assignment,  # e.g. 'r.NGX.DLSS.Quality=2'; a bare name only reads it
    [int]$Port = 8899
)
# Reads or sets live console variables through the uevr-mcp bridge. Changes are not persisted.
$ErrorActionPreference = 'Stop'
$base = "http://127.0.0.1:$Port"
foreach ($item in $Assignment) {
    $name, $value = $item -split '=', 2
    try { $before = Invoke-RestMethod "$base/api/console/cvar?name=$name" -TimeoutSec 5 }
    catch { [PSCustomObject]@{ Name = $name; Before = 'missing'; After = 'missing' }; continue }
    if ($null -ne $value) {
        $num = 0.0
        $v = if ([double]::TryParse($value, [Globalization.NumberStyles]::Float, [Globalization.CultureInfo]::InvariantCulture, [ref]$num)) { $num } else { $value }
        $body = @{ name = $name; value = $v } | ConvertTo-Json -Compress
        $r = Invoke-RestMethod -Method Post "$base/api/console/cvar" -Body $body -ContentType 'application/json' -TimeoutSec 5
        if ($r.error) { Write-Warning "${name}: $($r.error)"; continue }
    }
    $after = Invoke-RestMethod "$base/api/console/cvar?name=$name" -TimeoutSec 5
    [PSCustomObject]@{ Name = $name; Before = $before.float; After = $after.float }
}
