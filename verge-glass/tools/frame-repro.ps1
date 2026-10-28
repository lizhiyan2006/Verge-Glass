param(
    [ValidateSet('baseline', 'repro', 'ncrender', 'framechanged', 'region', 'recompose')][string]$Action = 'baseline',
    [string]$Out = "",
    [int]$Corner = 160
)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public class FRepro {
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
  [StructLayout(LayoutKind.Sequential)] public struct POINT { public int X, Y; }
  [DllImport("user32.dll")] public static extern bool ClientToScreen(IntPtr h, ref POINT p);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern bool GetClientRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int cmd);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr h, IntPtr after, int x, int y, int cx, int cy, uint flags);
  [DllImport("user32.dll")] public static extern bool RedrawWindow(IntPtr h, IntPtr rect, IntPtr rgn, uint flags);
  [DllImport("user32.dll")] public static extern int GetWindowRgn(IntPtr h, IntPtr rgn);
  [DllImport("dwmapi.dll")] public static extern int DwmSetWindowAttribute(IntPtr h, int attr, ref int value, int size);
  [DllImport("dwmapi.dll")] public static extern int DwmFlush();
  [DllImport("gdi32.dll")] public static extern IntPtr CreateRectRgn(int a, int b, int c, int d);
  [DllImport("gdi32.dll")] public static extern int SetWindowRgn(IntPtr h, IntPtr rgn, bool redraw);
  [DllImport("gdi32.dll")] public static extern bool DeleteObject(IntPtr o);
  [DllImport("shcore.dll")] public static extern int SetProcessDpiAwareness(int v);
}
'@
[void][FRepro]::SetProcessDpiAwareness(2)

$p = Get-Process clash-verge | Where-Object { $_.MainWindowHandle -ne 0 } | Select-Object -First 1
if (-not $p) { throw "no clash-verge window" }
$h = $p.MainWindowHandle

function Measure-Corner {
    $wr = New-Object FRepro+RECT
    [void][FRepro]::GetWindowRect($h, [ref]$wr)
    $cr = New-Object FRepro+RECT
    [void][FRepro]::GetClientRect($h, [ref]$cr)
    $pt = New-Object FRepro+POINT
    [void][FRepro]::ClientToScreen($h, [ref]$pt)
    $w = $wr.Right - $wr.Left; $ht = $wr.Bottom - $wr.Top
    $bmp = New-Object System.Drawing.Bitmap -ArgumentList @($w, $ht)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.CopyFromScreen($wr.Left, $wr.Top, 0, 0, (New-Object System.Drawing.Size -ArgumentList @($w, $ht)))
    $g.Dispose()
    if ($Out) {
        $cw = [int]$Corner
        $cw3 = $cw * 3
        $big = New-Object System.Drawing.Bitmap -ArgumentList @($cw3, $cw3)
        $gb = [System.Drawing.Graphics]::FromImage($big)
        $gb.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::NearestNeighbor
        $dst = New-Object System.Drawing.Rectangle -ArgumentList @(0, 0, $cw3, $cw3)
        $src = New-Object System.Drawing.Rectangle -ArgumentList @(($w - $cw), ($ht - $cw), $cw, $cw)
        $gb.DrawImage($bmp, $dst, $src, [System.Drawing.GraphicsUnit]::Pixel)
        $gb.Dispose()
        $big.Save($Out, [System.Drawing.Imaging.ImageFormat]::Png)
        $big.Dispose()
    }
    # A stale non-client ring / the 1px region slack both show up as a light neutral
    # line hugging the *client* edge, so scan a 2px band around the client boundary
    # (the window rect is 12px wider, that part is desktop and must stay desktop).
    $cx = $pt.X - $wr.Left
    $cy = $pt.Y - $wr.Top
    $rightBand = 0; $bottomBand = 0
    $rx = $cx + $cr.Right
    for ($x = $rx - 2; $x -le $rx + 1; $x++) {
        if ($x -lt 0 -or $x -ge $w) { continue }
        for ($y = 60; $y -lt $ht - 60; $y++) {
            $px = $bmp.GetPixel($x, $y)
            $mx = [Math]::Max($px.R, [Math]::Max($px.G, $px.B))
            $mn = [Math]::Min($px.R, [Math]::Min($px.G, $px.B))
            if (($mx - $mn) -le 16 -and $mx -ge 120) { $rightBand++ }
        }
    }
    $by = $cy + $cr.Bottom
    for ($y = $by - 2; $y -le $by + 1; $y++) {
        if ($y -lt 0 -or $y -ge $ht) { continue }
        for ($x = 60; $x -lt $w - 60; $x++) {
            $px = $bmp.GetPixel($x, $y)
            $mx = [Math]::Max($px.R, [Math]::Max($px.G, $px.B))
            $mn = [Math]::Min($px.R, [Math]::Min($px.G, $px.B))
            if (($mx - $mn) -le 16 -and $mx -ge 120) { $bottomBand++ }
        }
    }
    $rgn = [FRepro]::CreateRectRgn(0, 0, 0, 0)
    $type = [FRepro]::GetWindowRgn($h, $rgn)
    [void][FRepro]::DeleteObject($rgn)
    $bmp.Dispose()
    [ordered]@{
        window     = "${w}x${ht}"
        client     = "$($cr.Right)x$($cr.Bottom)"
        region     = "type=$type"
        rightBand  = $rightBand
        bottomBand = $bottomBand
    } | ConvertTo-Json -Compress
}

switch ($Action) {
    'baseline' { Measure-Corner }
    'repro' {
        [void][FRepro]::ShowWindow($h, 0)          # SW_HIDE
        Start-Sleep -Milliseconds 900
        [void][FRepro]::ShowWindow($h, 5)          # SW_SHOW
        [void][FRepro]::SetForegroundWindow($h)
        Start-Sleep -Milliseconds 1800
        Measure-Corner
    }
    'ncrender' {
        $one = 1
        $r = [FRepro]::DwmSetWindowAttribute($h, 2, [ref]$one, 4)   # DWMWA_NCRENDERING_POLICY = DWMNCRP_DISABLED
        "ncrender_policy=$r"
        Start-Sleep -Milliseconds 700
        Measure-Corner
    }
    'framechanged' {
        [void][FRepro]::SetWindowPos($h, [IntPtr]::Zero, 0, 0, 0, 0, 0x0020 -bor 0x0002 -bor 0x0001 -bor 0x0004 -bor 0x0010)  # FRAMECHANGED|NOMOVE|NOSIZE|NOZORDER|NOACTIVATE
        Start-Sleep -Milliseconds 700
        Measure-Corner
    }
    'region' {
        $wr = New-Object FRepro+RECT
        [void][FRepro]::GetWindowRect($h, [ref]$wr)
        $cr = New-Object FRepro+RECT
        [void][FRepro]::GetClientRect($h, [ref]$cr)
        $pt = New-Object FRepro+RECT
        $rgn = [FRepro]::CreateRectRgn(12, 0, 12 + $cr.Right + 1, $cr.Bottom + 1)
        [void][FRepro]::SetWindowRgn($h, $rgn, $true)
        Start-Sleep -Milliseconds 700
        Measure-Corner
    }
    'recompose' {
        [void][FRepro]::RedrawWindow($h, [IntPtr]::Zero, [IntPtr]::Zero, 0x0400 -bor 0x0080 -bor 0x0001 -bor 0x0100)  # FRAME|ALLCHILDREN|UPDATENOW|ERASE
        [void][FRepro]::DwmFlush()
        Start-Sleep -Milliseconds 700
        Measure-Corner
    }
}
