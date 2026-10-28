param([switch]$Restore, [string]$Shot = "$PSScriptRoot\..\shot-edge-style.png")
Add-Type -AssemblyName System.Drawing
Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public class FrameChk {
  [DllImport("user32.dll")] public static extern int GetWindowLong(IntPtr h, int i);
  [DllImport("user32.dll")] public static extern int SetWindowLong(IntPtr h, int i, int v);
  [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr h, IntPtr a, int x, int y, int cx, int cy, uint f);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
}
"@
[void][FrameChk]::SetProcessDPIAware()
$p = Get-Process clash-verge | Where-Object { $_.MainWindowHandle -ne 0 } | Select-Object -First 1
$h = $p.MainWindowHandle
$GWL_STYLE = -16
$style = [FrameChk]::GetWindowLong($h, $GWL_STYLE)
"style before: 0x{0:X}" -f $style
$WS_THICKFRAME = 0x00040000
if ($Restore) {
    [void][FrameChk]::SetWindowLong($h, $GWL_STYLE, $style -bor $WS_THICKFRAME)
} else {
    [void][FrameChk]::SetWindowLong($h, $GWL_STYLE, $style -band (-bnot $WS_THICKFRAME))
}
$SWP_NOMOVE = 0x0002; $SWP_NOSIZE = 0x0001; $SWP_NOZORDER = 0x0004; $SWP_FRAMECHANGED = 0x0020
[void][FrameChk]::SetWindowPos($h, [IntPtr]::Zero, 0, 0, 0, 0, $SWP_NOMOVE -bor $SWP_NOSIZE -bor $SWP_NOZORDER -bor $SWP_FRAMECHANGED)
Start-Sleep -Milliseconds 700
$style2 = [FrameChk]::GetWindowLong($h, $GWL_STYLE)
"style after:  0x{0:X}" -f $style2
$r = New-Object FrameChk+RECT
[void][FrameChk]::GetWindowRect($h, [ref]$r)
"rect: $($r.Left),$($r.Top) - $($r.Right),$($r.Bottom)"
$x0 = $r.Left - 12
$y0 = $r.Top + [int](($r.Bottom - $r.Top) / 2) - 40
$bmp = New-Object System.Drawing.Bitmap 70, 80
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.CopyFromScreen($x0, $y0, 0, 0, $bmp.Size)
$bmp.Save($Shot, [System.Drawing.Imaging.ImageFormat]::Png)
$g.Dispose(); $bmp.Dispose()
"saved $Shot"
