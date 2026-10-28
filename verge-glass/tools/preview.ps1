param(
    [string]$Css = "..\src\verge-glass.css",
    [string]$Tone = "dark",
    [string]$Alpha = "",
    [string]$Blur = "",
    [string]$Wallpaper = "",
    [string]$WallOpacity = "",
    [string]$Shot = "",
    [switch]$NoWallpaper
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent (Split-Path -Parent $PSCommandPath)
$cssPath = if ([IO.Path]::IsPathRooted($Css)) { $Css } else { Join-Path (Split-Path -Parent $PSCommandPath) $Css }
$cssText = [IO.File]::ReadAllText($cssPath, [Text.Encoding]::UTF8)

$override = "@@EOF@@"
$over = "`nhtml:root { "
if ($Alpha) { $over += "--vg-alpha: $Alpha; " }
if ($Blur) { $over += "--vg-blur: $Blur; " }
if ($Wallpaper -and -not $NoWallpaper) { $over += "--vg-wallpaper: url('$Wallpaper'); " }
if ($WallOpacity) { $over += "--vg-wall-opacity: $WallOpacity; " }
$over += "}`n"
$cssText = $cssText + $over

$payload = @{
    css = $cssText
    tone = $Tone
} | ConvertTo-Json -Compress
$tmp = Join-Path $env:TEMP "vg-payload.json"
[IO.File]::WriteAllText($tmp, $payload, [Text.Encoding]::UTF8)

$js = @'
(async () => {
  const p = __PAYLOAD__;
  let s = document.getElementById("vg-preview");
  if (!s) { s = document.createElement("style"); s.id = "vg-preview"; document.head.appendChild(s); }
  s.textContent = p.css;
  document.documentElement.setAttribute("data-vg-tone", p.tone);
  return "injected:" + p.css.length;
})()
'@
$jsPath = Join-Path $env:TEMP "vg-inject-preview.js"
$jsFile = Get-Content $tmp -Raw -Encoding UTF8
$js = $js.Replace("__PAYLOAD__", $jsFile)
[IO.File]::WriteAllText($jsPath, $js, [Text.Encoding]::UTF8)

$out = & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path (Split-Path -Parent $PSCommandPath) "cdp-eval.ps1") -ScriptFile $jsPath
Write-Output $out

if ($Shot) {
    Add-Type -AssemblyName System.Drawing
    Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public class VGW { [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r); [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; } }
public class VGD { [DllImport("user32.dll")] public static extern bool SetProcessDPIAware(); }
"@
    [void][VGD]::SetProcessDPIAware()
    $proc = Get-Process clash-verge -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowHandle -ne 0 } | Select-Object -First 1
    if (-not $proc) { Write-Error "no main window" }
    $r = New-Object VGW+RECT
    [void][VGW]::GetWindowRect($proc.MainWindowHandle, [ref]$r)
    $w = $r.Right - $r.Left; $h = $r.Bottom - $r.Top
    $bmp = New-Object System.Drawing.Bitmap $w, $h
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.CopyFromScreen($r.Left, $r.Top, 0, 0, $bmp.Size)
    $bmp.Save($Shot, [System.Drawing.Imaging.ImageFormat]::Png)
    $g.Dispose(); $bmp.Dispose()
    Write-Output "shot: $Shot"
}
