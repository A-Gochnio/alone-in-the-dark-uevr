[CmdletBinding()]
param(
    [ValidateSet('OpenXR', 'OpenVR')]
    [string]$Runtime = 'OpenXR',
    [string]$UevrDir = (Join-Path $env:APPDATA 'raicuparta\rai-pal\data\shared-mods\uevr-nightly'),
    [ValidateRange(10, 900)]
    [int]$WindowTimeoutSeconds = 180,
    [ValidateRange(0, 300)]
    [int]$SettleSeconds = 20,
    [ValidateRange(5, 600)]
    [int]$BridgeTimeoutSeconds = 60,
    [switch]$KeepOverlay,
    [switch]$NoBridge,
    [bool]$NullifyPlugins = $true,
    [int]$Port = 8899
)
# Headless replacement for the UEVR frontend's Inject button: LoadLibraryW the runtime loader,
# the plugin nullifier and UEVRBackend into the running game, then wait for the uevr-mcp bridge.
# Without the bridge (-NoBridge, or uevr_mcp.dll absent from the profile's plugins folder, as for play and
# benchmarks, where the plugin caps the game at ~42 FPS), injection is confirmed from the UEVR log and
# Insert is posted to the game window directly.
$ErrorActionPreference = 'Stop'

$gameProcessName = 'AloneInTheDark-Win64-Shipping'
$gameName = 'AloneInTheDark-Win64-Shipping.exe'
$base = "http://127.0.0.1:$Port"
$profileDir = Join-Path $env:APPDATA 'UnrealVRMod\AloneInTheDark-Win64-Shipping'
if (!$NoBridge -and !(Test-Path -LiteralPath (Join-Path $profileDir 'plugins\uevr_mcp.dll'))) {
    Write-Host 'uevr_mcp.dll is not in the profile; running without the bridge.'
    $NoBridge = [switch]$true
}

if (-not ('AitD.RemoteLoader' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
using System.Text;
namespace AitD {
public static class RemoteLoader {
    [DllImport("kernel32.dll", SetLastError = true)] static extern IntPtr OpenProcess(uint access, bool inherit, int pid);
    [DllImport("kernel32.dll", SetLastError = true)] static extern IntPtr VirtualAllocEx(IntPtr p, IntPtr addr, UIntPtr size, uint type, uint protect);
    [DllImport("kernel32.dll", SetLastError = true)] static extern bool VirtualFreeEx(IntPtr p, IntPtr addr, UIntPtr size, uint type);
    [DllImport("kernel32.dll", SetLastError = true)] static extern bool WriteProcessMemory(IntPtr p, IntPtr addr, byte[] buf, UIntPtr size, out UIntPtr written);
    [DllImport("kernel32.dll", SetLastError = true)] static extern IntPtr CreateRemoteThread(IntPtr p, IntPtr attr, UIntPtr stack, IntPtr start, IntPtr param, uint flags, IntPtr tid);
    [DllImport("kernel32.dll", SetLastError = true)] static extern uint WaitForSingleObject(IntPtr h, uint ms);
    [DllImport("kernel32.dll", SetLastError = true)] static extern bool GetExitCodeThread(IntPtr h, out uint code);
    [DllImport("kernel32.dll", SetLastError = true)] static extern bool CloseHandle(IntPtr h);
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)] static extern IntPtr GetModuleHandleW(string name);
    [DllImport("kernel32.dll", CharSet = CharSet.Ansi, SetLastError = true)] static extern IntPtr GetProcAddress(IntPtr mod, string name);
    [DllImport("user32.dll")] static extern bool PostMessageW(IntPtr h, uint msg, IntPtr w, IntPtr l);

    // WM_KEYDOWN/WM_KEYUP, as the bridge's key input does; the window does not need focus.
    public static void TapKey(IntPtr hwnd, int vk) {
        PostMessageW(hwnd, 0x100, (IntPtr)vk, (IntPtr)1);
        System.Threading.Thread.Sleep(80);
        PostMessageW(hwnd, 0x101, (IntPtr)vk, unchecked((IntPtr)(int)0xC0000001));
    }

    // PROCESS_CREATE_THREAD | QUERY_INFORMATION | VM_OPERATION | VM_WRITE | VM_READ
    public static void Load(int pid, string path, uint timeoutMs) {
        IntPtr proc = OpenProcess(0x043A, false, pid);
        if (proc == IntPtr.Zero) throw new Exception("OpenProcess failed: " + Marshal.GetLastWin32Error());
        try {
            byte[] bytes = Encoding.Unicode.GetBytes(path + "\0");
            UIntPtr size = (UIntPtr)bytes.Length;
            IntPtr mem = VirtualAllocEx(proc, IntPtr.Zero, size, 0x3000, 0x04);
            if (mem == IntPtr.Zero) throw new Exception("VirtualAllocEx failed: " + Marshal.GetLastWin32Error());
            try {
                UIntPtr written;
                if (!WriteProcessMemory(proc, mem, bytes, size, out written)) throw new Exception("WriteProcessMemory failed: " + Marshal.GetLastWin32Error());
                IntPtr loadLibrary = GetProcAddress(GetModuleHandleW("kernel32.dll"), "LoadLibraryW");
                IntPtr thread = CreateRemoteThread(proc, IntPtr.Zero, UIntPtr.Zero, loadLibrary, mem, 0, IntPtr.Zero);
                if (thread == IntPtr.Zero) throw new Exception("CreateRemoteThread failed: " + Marshal.GetLastWin32Error());
                try {
                    if (WaitForSingleObject(thread, timeoutMs) != 0) throw new Exception("LoadLibraryW thread timed out for " + path);
                } finally { CloseHandle(thread); }
            } finally { VirtualFreeEx(proc, mem, UIntPtr.Zero, 0x8000); }
        } finally { CloseHandle(proc); }
    }
}
}
'@
}

function Get-ModuleNames([System.Diagnostics.Process]$Process) {
    $Process.Refresh()
    try { @($Process.Modules | ForEach-Object { $_.ModuleName.ToLowerInvariant() }) } catch { @() }
}

function Get-BridgeGameInfo {
    try { Invoke-RestMethod "$base/api/game_info" -TimeoutSec 2 } catch { $null }
}

$loaderName = if ($Runtime -eq 'OpenXR') { 'openxr_loader.dll' } else { 'openvr_api.dll' }
$dlls = @($loaderName)
if ($NullifyPlugins) { $dlls += 'UEVRPluginNullifier.dll' }
$dlls += 'UEVRBackend.dll'
foreach ($dll in $dlls) {
    if (!(Test-Path -LiteralPath (Join-Path $UevrDir $dll))) { throw "Required UEVR file is missing: $(Join-Path $UevrDir $dll)" }
}

# Wait for the game window and its renderer.
$deadline = [DateTime]::UtcNow.AddSeconds($WindowTimeoutSeconds)
$game = $null
do {
    $game = Get-Process -Name $gameProcessName -ErrorAction SilentlyContinue | Select-Object -First 1
    $ready = $false
    if ($game -and $game.MainWindowHandle -ne [IntPtr]::Zero) {
        $modules = Get-ModuleNames $game
        $ready = ($modules -contains 'd3d12.dll') -or ($modules -contains 'd3d11.dll')
    }
    if (!$ready) { Start-Sleep -Milliseconds 500 }
} until ($ready -or [DateTime]::UtcNow -ge $deadline)
if (!$ready) { throw "The game window with a D3D renderer did not appear within $WindowTimeoutSeconds seconds." }

$info = if ($NoBridge) { $null } else { Get-BridgeGameInfo }
$injected = @()
$injectStart = Get-Date
if ($info -and $info.gameName -eq $gameName) {
    Write-Host "UEVR bridge already answers for PID $($game.Id); skipping injection."
} else {
    $modules = Get-ModuleNames $game
    if ($modules -notcontains 'uevrbackend.dll') {
        Write-Host "Renderer is up in PID $($game.Id); settling for $SettleSeconds s before injecting..."
        Start-Sleep -Seconds $SettleSeconds
    }
    foreach ($dll in $dlls) {
        $modules = Get-ModuleNames $game
        if ($modules -contains $dll.ToLowerInvariant()) { Write-Host "$dll is already loaded."; continue }
        Write-Host "Injecting $dll..."
        [AitD.RemoteLoader]::Load($game.Id, (Join-Path $UevrDir $dll), 30000)
        if ((Get-ModuleNames $game) -notcontains $dll.ToLowerInvariant()) { throw "$dll did not load into PID $($game.Id)." }
        $injected += $dll
    }

    $deadline = [DateTime]::UtcNow.AddSeconds($BridgeTimeoutSeconds)
    if ($NoBridge) {
        # UEVR rewrites log.txt on injection; creating the eye swapchains means the OpenXR session is up.
        $log = Join-Path $profileDir 'log.txt'
        $text = ''
        do {
            Start-Sleep -Seconds 2
            if ((Test-Path -LiteralPath $log) -and (Get-Item -LiteralPath $log).LastWriteTime -ge $injectStart) {
                $text = Get-Content -LiteralPath $log -Raw
            }
        } until ($text -match 'Runtime wants \d+ images for swapchain' -or [DateTime]::UtcNow -ge $deadline)
        # Some XR errors are benign (XR_ERROR_PATH_UNSUPPORTED for unused bindings), so they only explain a timeout.
        if ($text -notmatch 'Runtime wants \d+ images for swapchain') {
            $errors = ([regex]::Matches($text, 'XR_ERROR_\w+') | ForEach-Object Value | Select-Object -Unique) -join ', '
            throw "UEVR did not create its OpenXR swapchains within $BridgeTimeoutSeconds seconds. XR errors: $errors (XR_ERROR_FORM_FACTOR_UNAVAILABLE means the headset is not connected to Virtual Desktop)."
        }
    } else {
        do {
            Start-Sleep -Seconds 2
            $info = Get-BridgeGameInfo
        } until (($info -and $info.gameName -eq $gameName) -or [DateTime]::UtcNow -ge $deadline)
        if (!($info -and $info.gameName -eq $gameName)) { throw "The uevr-mcp bridge did not answer within $BridgeTimeoutSeconds seconds." }
    }
}

$status = if ($NoBridge) { $null } else { Invoke-RestMethod "$base/api/vr/status" -TimeoutSec 5 }

$overlayCloseSent = $false
if (!$KeepOverlay) {
    Start-Sleep -Seconds 3
    if ($NoBridge) {
        $game.Refresh()
        [AitD.RemoteLoader]::TapKey($game.MainWindowHandle, 0x2D)
    } else {
        $body = @{ key = 'insert' } | ConvertTo-Json -Compress
        Invoke-RestMethod -Method Post "$base/api/input/key" -Body $body -ContentType 'application/json' -TimeoutSec 5 | Out-Null
    }
    $overlayCloseSent = $true
}

[PSCustomObject]@{
    GamePid = $game.Id
    Runtime = $Runtime
    Injected = $injected -join ', '
    Bridge = !$NoBridge
    RuntimeReady = $status.runtimeReady
    HmdActive = $status.hmdActive
    UsingControllers = $status.usingControllers
    OverlayCloseSent = $overlayCloseSent
}
