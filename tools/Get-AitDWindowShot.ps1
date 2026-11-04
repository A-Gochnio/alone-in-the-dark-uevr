<#
.SYNOPSIS
Captures the game window to a PNG and optionally posts keys to it first.

.DESCRIPTION
Uses CopyFromScreen on the game window's rectangle, so the window must be visible
(wherever it sits). Keys are posted as WM_KEYDOWN/WM_KEYUP, which the game reads
without focus, the same way Invoke-AitDUevrInject.ps1 sends Insert.

.EXAMPLE
./tools/Get-AitDWindowShot.ps1 -Keys Escape -DelayMs 800 -Out local/ui-captures/pause.png
#>
param(
    [string]$Out = "local/ui-captures/shot-$(Get-Date -Format yyyyMMdd-HHmmss).png",
    [string[]]$Keys = @(),
    [int]$DelayMs = 600,
    [int]$HoldMs = 60
)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing, System.Windows.Forms
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class AitDWin {
    [StructLayout(LayoutKind.Sequential)] public struct RECT { public int L, T, R, B; }
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
    [DllImport("user32.dll")] public static extern bool PostMessageW(IntPtr h, uint msg, IntPtr w, IntPtr l);
    [DllImport("user32.dll")] public static extern uint MapVirtualKeyW(uint code, uint type);
    public static void Key(IntPtr h, int vk, int holdMs) {
        long sc = MapVirtualKeyW((uint)vk, 0) << 16;
        PostMessageW(h, 0x100, (IntPtr)vk, (IntPtr)(1 | sc));
        System.Threading.Thread.Sleep(holdMs);
        PostMessageW(h, 0x101, (IntPtr)vk, unchecked((IntPtr)(int)(0xC0000001 | sc)));
    }
}
'@ -ErrorAction SilentlyContinue

$proc = Get-Process AloneInTheDark-Win64-Shipping -ErrorAction Stop | Select-Object -First 1
$hwnd = $proc.MainWindowHandle
if ($hwnd -eq [IntPtr]::Zero) { throw 'Game window not found.' }

foreach ($k in $Keys) {
    if ($k -match '^sleep(\d+)$') { Start-Sleep -Milliseconds ([int]$Matches[1]); continue }
    $vk = [int][System.Windows.Forms.Keys]::$k
    [AitDWin]::Key($hwnd, $vk, $HoldMs)
    Start-Sleep -Milliseconds 250
}
if ($Keys.Count) { Start-Sleep -Milliseconds $DelayMs }

$r = New-Object AitDWin+RECT
[void][AitDWin]::GetWindowRect($hwnd, [ref]$r)
$w = $r.R - $r.L; $h = $r.B - $r.T
$bmp = New-Object System.Drawing.Bitmap $w, $h
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.CopyFromScreen($r.L, $r.T, 0, 0, $bmp.Size)
$dir = Split-Path -Parent $Out
if ($dir) { New-Item -ItemType Directory -Force $dir | Out-Null }
$bmp.Save((Join-Path (Resolve-Path .) $Out), [System.Drawing.Imaging.ImageFormat]::Png)
$g.Dispose(); $bmp.Dispose()
"$Out ${w}x$h at ($($r.L),$($r.T))"
