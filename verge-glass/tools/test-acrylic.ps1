param([int]$Alpha = 200, [int]$Accent = 4, [uint32]$Gradient = 0x99000000, [switch]$Clear)
Add-Type -AssemblyName System.Drawing
Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public class Acr {
  [DllImport("user32.dll")] public static extern bool SetLayeredWindowAttributes(IntPtr hwnd, uint crKey, byte bAlpha, uint dwFlags);
  [DllImport("user32.dll")] public static extern int GetWindowLong(IntPtr hWnd, int nIndex);
  [DllImport("user32.dll")] public static extern int SetWindowLong(IntPtr hWnd, int nIndex, int dwNewLong);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hWnd, out RECT r);
  [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
  [DllImport("user32.dll")] public static extern int SetWindowCompositionAttribute(IntPtr hwnd, ref WCADATA data);
  [DllImport("dwmapi.dll")] public static extern int DwmSetWindowAttribute(IntPtr hwnd, int attr, ref int value, int size);

  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
  [StructLayout(LayoutKind.Sequential)] public struct ACCENTPOLICY {
    public int AccentState;
    public int AccentFlags;
    public uint GradientColor;
    public int AnimationId;
  }
  [StructLayout(LayoutKind.Sequential)] public struct WCADATA {
    public int Attribute;
    public IntPtr Data;
    public int SizeOfData;
  }
}
"@
[void][Acr]::SetProcessDPIAware()
$p = Get-Process clash-verge | Where-Object { $_.MainWindowHandle -ne 0 } | Select-Object -First 1
$h = $p.MainWindowHandle
$GWL_EXSTYLE = -20; $WS_EX_LAYERED = 0x00080000
$style = [Acr]::GetWindowLong($h, $GWL_EXSTYLE)

if ($Clear) {
    [void][Acr]::SetWindowLong($h, $GWL_EXSTYLE, $style -band (-bnot $WS_EX_LAYERED))
    $policy = New-Object Acr+ACCENTPOLICY
    $policy.AccentState = 0
    $policy.AccentFlags = 0
    $policy.GradientColor = 0
    $policy.AnimationId = 0
    $ptr = [Runtime.InteropServices.Marshal]::AllocHGlobal([Runtime.InteropServices.Marshal]::SizeOf($policy))
    [Runtime.InteropServices.Marshal]::StructureToPtr($policy, $ptr, $false)
    $data = New-Object Acr+WCADATA
    $data.Attribute = 19
    $data.Data = $ptr
    $data.SizeOfData = [Runtime.InteropServices.Marshal]::SizeOf($policy)
    [void][Acr]::SetWindowCompositionAttribute($h, [ref]$data)
    [Runtime.InteropServices.Marshal]::FreeHGlobal($ptr)
    "cleared"
    exit 0
}

[void][Acr]::SetWindowLong($h, $GWL_EXSTYLE, $style -bor $WS_EX_LAYERED)
[void][Acr]::SetLayeredWindowAttributes($h, 0, [byte]$Alpha, 2)

$policy = New-Object Acr+ACCENTPOLICY
$policy.AccentState = $Accent
$policy.AccentFlags = 2
$policy.GradientColor = $Gradient
$policy.AnimationId = 0
$ptr = [Runtime.InteropServices.Marshal]::AllocHGlobal([Runtime.InteropServices.Marshal]::SizeOf($policy))
[Runtime.InteropServices.Marshal]::StructureToPtr($policy, $ptr, $false)
$data = New-Object Acr+WCADATA
$data.Attribute = 19
$data.Data = $ptr
$data.SizeOfData = [Runtime.InteropServices.Marshal]::SizeOf($policy)
$res = [Acr]::SetWindowCompositionAttribute($h, [ref]$data)
[Runtime.InteropServices.Marshal]::FreeHGlobal($ptr)

$dark = 1
[void][Acr]::DwmSetWindowAttribute($h, 20, [ref]$dark, 4)
"accent=$Accent result=$res alpha=$Alpha"

Start-Sleep -Milliseconds 700
$r = New-Object Acr+RECT
[void][Acr]::GetWindowRect($h, [ref]$r)
$w = $r.Right - $r.Left; $hh = $r.Bottom - $r.Top
$bmp = New-Object System.Drawing.Bitmap $w, $hh
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.CopyFromScreen($r.Left, $r.Top, 0, 0, $bmp.Size)
$out = Join-Path $PSScriptRoot "..\shot-acrylic.png"
$bmp.Save($out, [System.Drawing.Imaging.ImageFormat]::Png)
$g.Dispose(); $bmp.Dispose()
"saved $out"
