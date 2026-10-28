# Native-side guard for the fork window shell (things the page cannot see):
#   * no WS_CAPTION / WS_THICKFRAME  -> Windows must not paint a title bar over the glass
#   * a window region exists          -> the DWM frame follows the rounded corners
#   * region covers the client area   -> the anti-aliased CSS corners are never clipped
# Run: powershell -File tools\verify-window.ps1
param([string]$ProcessName = 'clash-verge')

Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public class VGWinCheck {
  [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
  [DllImport("user32.dll")] public static extern int GetWindowLong(IntPtr h, int i);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern bool GetClientRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern int GetWindowRgn(IntPtr h, IntPtr rgn);
  [DllImport("user32.dll")] public static extern bool ClientToScreen(IntPtr h, ref POINT p);
  [DllImport("gdi32.dll")] public static extern IntPtr CreateRectRgn(int a, int b, int c, int d);
  [DllImport("gdi32.dll")] public static extern int GetRgnBox(IntPtr rgn, out RECT r);
  [DllImport("gdi32.dll")] public static extern bool DeleteObject(IntPtr o);
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int L, T, R, B; }
  [StructLayout(LayoutKind.Sequential)] public struct POINT { public int x, y; }
}
'@

[void][VGWinCheck]::SetProcessDPIAware()
$proc = Get-Process $ProcessName -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowHandle -ne 0 } | Select-Object -First 1
if (-not $proc) { Write-Error "no window for process $ProcessName"; exit 1 }
$h = $proc.MainWindowHandle

$style = [VGWinCheck]::GetWindowLong($h, -16)
$hasCaption = [bool]($style -band 0x00C00000)
$hasThick = [bool]($style -band 0x00040000)

$wr = New-Object VGWinCheck+RECT; [void][VGWinCheck]::GetWindowRect($h, [ref]$wr)
$cr = New-Object VGWinCheck+RECT; [void][VGWinCheck]::GetClientRect($h, [ref]$cr)
$rgn = [VGWinCheck]::CreateRectRgn(0, 0, 0, 0)
$type = [VGWinCheck]::GetWindowRgn($h, $rgn)
$rb = New-Object VGWinCheck+RECT; [void][VGWinCheck]::GetRgnBox($rgn, [ref]$rb)
[void][VGWinCheck]::DeleteObject($rgn)

$problems = @()
if ($hasCaption) { $problems += 'WS_CAPTION is back (Windows will draw a title bar over the glass)' }
if ($hasThick) { $problems += 'WS_THICKFRAME is back (native sizing border reappears)' }
if ($type -eq 0) { $problems += 'window has no region (the white non-client ring will show)' }

# Sizes only: coordinates from GetWindowRect/ClientToScreen get virtualised on
# mixed-DPI monitors, while the sizes stay trustworthy. The region must be exactly
# the client area: one pixel of slack on the right/bottom edge is a non-client pixel,
# and the window class brush paints those white (that 1px bright line along the glass).
$regionW = $rb.R - $rb.L
$regionH = $rb.B - $rb.T
if ($type -ne 0 -and ($regionW -ne $cr.R -or $regionH -ne $cr.B)) {
    $problems += "region != client (client $($cr.R)x$($cr.B), region ${regionW}x${regionH})"
}

$result = [ordered]@{
    ok        = ($problems.Count -eq 0)
    problems  = $problems
    style     = ('0x{0:X8}' -f ($style -band 0xFFFFFFFF))
    caption   = $hasCaption
    thickframe = $hasThick
    window    = "$($wr.R - $wr.L)x$($wr.B - $wr.T)"
    client    = "$($cr.R)x$($cr.B)"
    region    = "($($rb.L),$($rb.T))-($($rb.R),$($rb.B))"
}
$result | ConvertTo-Json -Compress
if ($problems.Count -gt 0) { exit 2 }
