param([string]$Shot = "$PSScriptRoot\..\shot-edge.png", [switch]$ExtendAll)
Add-Type -AssemblyName System.Drawing
Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public class EdgeChk {
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("dwmapi.dll")] public static extern int DwmGetWindowAttribute(IntPtr hwnd, int attr, out RECT r, int size);
  [DllImport("dwmapi.dll")] public static extern int DwmExtendFrameIntoClientArea(IntPtr hwnd, ref MARGINS m);
  [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
  [StructLayout(LayoutKind.Sequential)] public struct MARGINS { public int cxLeftWidth, cxRightWidth, cyTopHeight, cyBottomHeight; }
}
"@
[void][EdgeChk]::SetProcessDPIAware()
$p = Get-Process clash-verge | Where-Object { $_.MainWindowHandle -ne 0 } | Select-Object -First 1
$h = $p.MainWindowHandle
$r = New-Object EdgeChk+RECT
[void][EdgeChk]::GetWindowRect($h, [ref]$r)
$e = New-Object EdgeChk+RECT
[void][EdgeChk]::DwmGetWindowAttribute($h, 9, [ref]$e, 16)
"window rect: $($r.Left),$($r.Top) - $($r.Right),$($r.Bottom)"
"visible rect: $($e.Left),$($e.Top) - $($e.Right),$($e.Bottom)"
"insets: left=$($e.Left-$r.Left) top=$($e.Top-$r.Top) right=$($r.Right-$e.Right) bottom=$($r.Bottom-$e.Bottom)"

if ($ExtendAll) {
  $m = New-Object EdgeChk+MARGINS
  $m.cxLeftWidth = -1; $m.cxRightWidth = -1; $m.cyTopHeight = -1; $m.cyBottomHeight = -1
  $res = [EdgeChk]::DwmExtendFrameIntoClientArea($h, [ref]$m)
  "extend all = $res"
  Start-Sleep -Milliseconds 600
}

# capture strip across the left edge
$x0 = $r.Left - 12
$y0 = $r.Top + [int](($r.Bottom - $r.Top) / 2) - 40
$w = 70
$hh = 80
$bmp = New-Object System.Drawing.Bitmap $w, $hh
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.CopyFromScreen($x0, $y0, 0, 0, $bmp.Size)
$bmp.Save($Shot, [System.Drawing.Imaging.ImageFormat]::Png)
$g.Dispose(); $bmp.Dispose()
"saved $Shot"
