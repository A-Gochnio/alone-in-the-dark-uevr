<#
.SYNOPSIS
Plugs a virtual Xbox 360 pad through the ViGEmBus driver and replays tools/Send-AitDSimQuest.ps1 commands on it.

.DESCRIPTION
Test-only. UEVR reports Quest controllers to the game as an XInput pad (grips = LB/RB, triggers =
LT/RT, A/B/X/Y, sticks, stick clicks), and profile/scripts/alone_in_the_dark_vr.lua remaps that
pad state in its XInput callback. A physical (here: virtual) XInput pad goes through the same
callback, so this exercises the real remap without the headset on. Talks to the bus directly with
DeviceIoControl (no ViGEmClient DLL). Needs ViGEmBus installed. Runs until -Seconds elapse or the
window is closed; unplugs the pad on exit.

Command file: %APPDATA%\UnrealVRMod\AloneInTheDark-Win64-Shipping\data\aitd_pad_input.txt
  seq=<n> buttons=A,RB,LS lt=<0-255> rt=<0-255> lx= ly= rx= ry= dur=<seconds>
#>
param([int]$Seconds = 7200)
$ErrorActionPreference = 'Stop'
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
using Microsoft.Win32.SafeHandles;
public static class AitDVigem {
    static readonly Guid BusGuid = new Guid("96E42B22-F5E9-42F8-B043-ED0F932F014F");
    const uint FILE_DEVICE_BUSENUM = 0x2A, METHOD_BUFFERED = 0, FILE_READ = 1, FILE_WRITE = 2;
    static uint Ctl(uint index, uint access) { return (FILE_DEVICE_BUSENUM << 16) | (access << 14) | (index << 2) | METHOD_BUFFERED; }
    static readonly uint PLUGIN = Ctl(0x801, FILE_WRITE), UNPLUG = Ctl(0x802, FILE_WRITE),
        CHECK_VERSION = Ctl(0x803, FILE_WRITE), WAIT_READY = Ctl(0x804, FILE_WRITE), SUBMIT = Ctl(0xA02, FILE_WRITE);

    [StructLayout(LayoutKind.Sequential)] struct SP_DEVICE_INTERFACE_DATA { public int cbSize; public Guid InterfaceClassGuid; public int Flags; public IntPtr Reserved; }
    [DllImport("setupapi.dll", SetLastError = true)] static extern IntPtr SetupDiGetClassDevs(ref Guid g, IntPtr e, IntPtr h, int flags);
    [DllImport("setupapi.dll", SetLastError = true)] static extern bool SetupDiEnumDeviceInterfaces(IntPtr set, IntPtr info, ref Guid g, int idx, ref SP_DEVICE_INTERFACE_DATA d);
    [DllImport("setupapi.dll", SetLastError = true, CharSet = CharSet.Unicode)] static extern bool SetupDiGetDeviceInterfaceDetail(IntPtr set, ref SP_DEVICE_INTERFACE_DATA d, IntPtr detail, int size, out int required, IntPtr info);
    [DllImport("setupapi.dll")] static extern bool SetupDiDestroyDeviceInfoList(IntPtr set);
    [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)] static extern SafeFileHandle CreateFile(string name, uint access, uint share, IntPtr sec, uint disp, uint flags, IntPtr tmpl);
    [DllImport("kernel32.dll", SetLastError = true)] static extern bool DeviceIoControl(SafeFileHandle h, uint code, byte[] inBuf, int inLen, byte[] outBuf, int outLen, out int ret, IntPtr ov);

    static SafeFileHandle bus;
    const uint Serial = 1;

    static string BusPath() {
        Guid g = BusGuid;
        IntPtr set = SetupDiGetClassDevs(ref g, IntPtr.Zero, IntPtr.Zero, 0x12); // PRESENT | DEVICEINTERFACE
        try {
            var d = new SP_DEVICE_INTERFACE_DATA(); d.cbSize = Marshal.SizeOf(d);
            if (!SetupDiEnumDeviceInterfaces(set, IntPtr.Zero, ref g, 0, ref d)) throw new Exception("ViGEmBus not found (is it installed?)");
            int req; SetupDiGetDeviceInterfaceDetail(set, ref d, IntPtr.Zero, 0, out req, IntPtr.Zero);
            IntPtr buf = Marshal.AllocHGlobal(req);
            try {
                Marshal.WriteInt32(buf, IntPtr.Size == 8 ? 8 : 6);
                if (!SetupDiGetDeviceInterfaceDetail(set, ref d, buf, req, out req, IntPtr.Zero)) throw new Exception("detail " + Marshal.GetLastWin32Error());
                return Marshal.PtrToStringUni(buf + 4);
            } finally { Marshal.FreeHGlobal(buf); }
        } finally { SetupDiDestroyDeviceInfoList(set); }
    }
    static void Io(uint code, byte[] b) {
        int ret;
        if (!DeviceIoControl(bus, code, b, b.Length, b, b.Length, out ret, IntPtr.Zero))
            throw new Exception(string.Format("IOCTL 0x{0:X} failed: {1}", code, Marshal.GetLastWin32Error()));
    }
    static byte[] U32s(params uint[] v) { var b = new byte[v.Length * 4]; for (int i = 0; i < v.Length; i++) BitConverter.GetBytes(v[i]).CopyTo(b, i * 4); return b; }

    public static void Plug() {
        bus = CreateFile(BusPath(), 0xC0000000, 3, IntPtr.Zero, 3, 0, IntPtr.Zero);
        if (bus.IsInvalid) throw new Exception("open bus " + Marshal.GetLastWin32Error());
        Io(CHECK_VERSION, U32s(8, 1));
        var p = new byte[16];
        BitConverter.GetBytes(16u).CopyTo(p, 0); BitConverter.GetBytes(Serial).CopyTo(p, 4);
        BitConverter.GetBytes(0u).CopyTo(p, 8);              // Xbox360Wired
        BitConverter.GetBytes((ushort)0x045E).CopyTo(p, 12); // Microsoft
        BitConverter.GetBytes((ushort)0x028E).CopyTo(p, 14); // Xbox 360 Controller
        Io(PLUGIN, p);
        try { Io(WAIT_READY, U32s(8, Serial)); } catch { }
    }
    public static void Submit(ushort buttons, byte lt, byte rt, short lx, short ly, short rx, short ry) {
        var b = new byte[20];
        BitConverter.GetBytes(20u).CopyTo(b, 0); BitConverter.GetBytes(Serial).CopyTo(b, 4);
        BitConverter.GetBytes(buttons).CopyTo(b, 8); b[10] = lt; b[11] = rt;
        BitConverter.GetBytes(lx).CopyTo(b, 12); BitConverter.GetBytes(ly).CopyTo(b, 14);
        BitConverter.GetBytes(rx).CopyTo(b, 16); BitConverter.GetBytes(ry).CopyTo(b, 18);
        Io(SUBMIT, b);
    }
    public static void Unplug() {
        if (bus == null || bus.IsInvalid) return;
        try { Io(UNPLUG, U32s(8, Serial)); } catch { }
        bus.Dispose();
    }
}
'@
$map = @{ DPAD_UP = 0x1; DPAD_DOWN = 0x2; DPAD_LEFT = 0x4; DPAD_RIGHT = 0x8; START = 0x10; BACK = 0x20; LS = 0x40; RS = 0x80;
    LB = 0x100; RB = 0x200; A = 0x1000; B = 0x2000; X = 0x4000; Y = 0x8000 }
$file = Join-Path $env:APPDATA 'UnrealVRMod\AloneInTheDark-Win64-Shipping\data\aitd_pad_input.txt'
function Num($text, $key) { $m = [regex]::Match([string]$text,"\b$key=(-?[\d.]+)"); if ($m.Success) { [double]::Parse($m.Groups[1].Value, [Globalization.CultureInfo]::InvariantCulture) } else { 0 } }

[AitDVigem]::Plug()
Write-Host 'Virtual Xbox 360 pad plugged in.'
$lastSeq = $null
try { $lastSeq = [regex]::Match([string][IO.File]::ReadAllText($file), 'seq=(\d+)').Groups[1].Value } catch { }
$until = [DateTime]::MinValue
$cur = @(0, 0, 0, 0, 0, 0, 0)
$end = (Get-Date).AddSeconds($Seconds)
try {
    while ((Get-Date) -lt $end) {
        $t = ''
        try { $t = [string][IO.File]::ReadAllText($file) } catch { }
        if ($t) {
            $seq = [regex]::Match($t, 'seq=(\d+)').Groups[1].Value
            if ($seq -and $seq -ne $lastSeq) {
                $lastSeq = $seq
                $btn = 0
                foreach ($n in ([regex]::Match($t, 'buttons=([\w,]*)').Groups[1].Value -split ',')) { if ($map.ContainsKey($n)) { $btn = $btn -bor $map[$n] } }
                $cur = @($btn, (Num $t 'lt'), (Num $t 'rt'), (Num $t 'lx'), (Num $t 'ly'), (Num $t 'rx'), (Num $t 'ry'))
                $dur = Num $t 'dur'; if ($dur -le 0) { $dur = 0.2 }
                $until = (Get-Date).AddSeconds($dur)
            }
        }
        if ((Get-Date) -gt $until) { $cur = @(0, 0, 0, 0, 0, 0, 0) }
        [AitDVigem]::Submit([uint16]$cur[0], [byte]$cur[1], [byte]$cur[2], [int16]$cur[3], [int16]$cur[4], [int16]$cur[5], [int16]$cur[6])
        Start-Sleep -Milliseconds 8
    }
} finally {
    [AitDVigem]::Unplug()
    Write-Host 'Virtual pad unplugged.'
}
