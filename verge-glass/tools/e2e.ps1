param(
    [string]$Shot = "",
    [switch]$KeepSize,
    [int]$Width = 1645,
    [int]$Height = 1225
)
$ErrorActionPreference = "Stop"
Add-Type -TypeDefinition 'using System;using System.Runtime.InteropServices;public class VGS{[DllImport("user32.dll")]public static extern bool SetWindowPos(IntPtr h,IntPtr a,int x,int y,int cx,int cy,uint f);}'
if (-not $KeepSize) {
    $p = Get-Process clash-verge -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowHandle -ne 0 } | Select-Object -First 1
    if ($p) { [void][VGS]::SetWindowPos($p.MainWindowHandle, [IntPtr]::Zero, 260, 40, $Width, $Height, 0x0040); Start-Sleep -Milliseconds 700 }
}
$cdp = Join-Path $PSScriptRoot "cdp-eval.ps1"

$navJs = @'
(() => { const m = document.querySelector("ul.the-menu"); if (!m) return "no-menu"; m.children[7].querySelector("[role=button]").click(); return "ok"; })()
'@
$scrollJs = @'
(() => { const c = document.querySelector(".the-content .base-container") || document.querySelector(".the-content"); if (c) c.scrollTop = c.scrollHeight; window.__VERGE_GLASS__ && window.__VERGE_GLASS__.mount(true); return "scrolled"; })()
'@
$navPath = Join-Path $env:TEMP "vg-nav.js"
$scrollPath = Join-Path $env:TEMP "vg-scroll.js"
[IO.File]::WriteAllText($navPath, $navJs, [Text.Encoding]::UTF8)
[IO.File]::WriteAllText($scrollPath, $scrollJs, [Text.Encoding]::UTF8)

& powershell -NoProfile -NoLogo -ExecutionPolicy Bypass -File $cdp -ScriptFile $navPath | Out-Null
Start-Sleep -Milliseconds 800
& powershell -NoProfile -NoLogo -ExecutionPolicy Bypass -File $cdp -ScriptFile $scrollPath | Out-Null
Start-Sleep -Milliseconds 600
if ($Shot) {
    & powershell -NoProfile -NoLogo -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot "cdp-shot.ps1") -Out $Shot
}
