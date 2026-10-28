param([int]$Alpha = 200, [switch]$Clear)
Add-Type -AssemblyName System.Drawing
Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public class Layered {
  [DllImport("user32.dll")] public static extern bool SetLayeredWindowAttributes(IntPtr hwnd, uint crKey, byte bAlpha, uint dwFlags);
  [DllImport("user32.dll")] public static extern int GetWindowLong(IntPtr hWnd, int nIndex);
  [DllImport("user32.dll")] public static extern int SetWindowLong(IntPtr hWnd, int nIndex, int dwNewLong);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hWnd, out RECT r);
  [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
}
"@
[void][Layered]::SetProcessDPIAware()
$p = Get-Process clash-verge | Where-Object { $_.MainWindowHandle -ne 0 } | Select-Object -First 1
$h = $p.MainWindowHandle
$GWL_EXSTYLE = -20
$WS_EX_LAYERED = 0x00080000
$LWA_ALPHA = 0x2
$style = [Layered]::GetWindowLong($h, $GWL_EXSTYLE)
if ($Clear) {
    $new = $style -band (-bnot $WS_EX_LAYERED)
    [void][Layered]::SetWindowLong($h, $GWL_EXSTYLE, $new)
    "cleared layered (style was $style)"
    exit 0
}
[void][Layered]::SetWindowLong($h, $GWL_EXSTYLE, $style -bor $WS_EX_LAYERED)
$ok = [Layered]::SetLayeredWindowAttributes($h, 0, [byte]$Alpha, $LWA_ALPHA)
"layered style=$style set=$ok alpha=$Alpha"
Start-Sleep -Milliseconds 600
$r = New-Object Layered+RECT
[void][Layered]::GetWindowRect($h, [ref]$r)
$w = $r.Right - $r.Left; $hh = $r.Bottom - $r.Top
$bmp = New-Object System.Drawing.Bitmap $w, $hh
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.CopyFromScreen($r.Left, $r.Top, 0, 0, $bmp.Size)
$out = Join-Path $PSScriptRoot "..\shot-layered.png"
$bmp.Save($out, [System.Drawing.Imaging.ImageFormat]::Png)
$g.Dispose(); $bmp.Dispose()
"saved $out"
