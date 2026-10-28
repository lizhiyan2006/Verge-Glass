param(
    [string]$Tone = "",
    [string]$Shot = "",
    [switch]$NoShot
)
$ErrorActionPreference = "Stop"
$root = Split-Path -Parent (Split-Path -Parent $PSCommandPath)
$css = [IO.File]::ReadAllText((Join-Path $root "src\verge-glass.css"), [Text.Encoding]::UTF8)
$js = [IO.File]::ReadAllText((Join-Path $root "src\verge-glass.js"), [Text.Encoding]::UTF8)

$wall = "http://asset.localhost/C%3A%5CUsers%5C394%5CAppData%5CRoaming%5CMicrosoft%5CWindows%5CThemes%5CTranscodedWallpaper"
$vgHost = @{
    version    = ((Get-Content (Join-Path $root "plugin.json") -Raw | ConvertFrom-Json).version)
    appVersion = "2.5.8"
    css        = $css
    wallpaper  = $wall
} | ConvertTo-Json -Compress

$payload = @{ host = $vgHost; js = $js; tone = $Tone } | ConvertTo-Json -Compress
$plPath = Join-Path $env:TEMP "vg-host.json"
[IO.File]::WriteAllText($plPath, $payload, [Text.Encoding]::UTF8)

$driver = @'
(async () => {
  const p = __PAYLOAD__;
  window.__VG_HOST__ = JSON.parse(p.host);
  window.__VERGE_GLASS_READY__ = false;
  window.__VG_BOOT_SCHEDULED__ = false;
  window.__VERGE_GLASS__ = undefined;
  const old = document.getElementById("verge-glass"); if (old) old.remove();
  const oldCard = document.getElementById("vg-card"); if (oldCard) oldCard.remove();
  (0, eval)(p.js);
  await new Promise((r) => setTimeout(r, 250));
  if (p.tone) document.documentElement.setAttribute("data-vg-tone", p.tone);
  if (!window.__VERGE_GLASS__) return "boot failed";
  window.__VERGE_GLASS__.mount(true);
  return "ok v" + window.__VERGE_GLASS__.version + " css=" + (document.getElementById("verge-glass") ? document.getElementById("verge-glass").textContent.length : 0);
})()
'@
$jsPath = Join-Path $env:TEMP "vg-driver.js"
[IO.File]::WriteAllText($jsPath, $driver.Replace("__PAYLOAD__", (Get-Content $plPath -Raw -Encoding UTF8)), [Text.Encoding]::UTF8)

$cdp = Join-Path $PSScriptRoot "cdp-eval.ps1"
$out = & powershell -NoProfile -NoLogo -ExecutionPolicy Bypass -File $cdp -ScriptFile $jsPath
Write-Output $out

if (-not $NoShot) {
    $nav = '(() => { const m = document.querySelector("ul.the-menu"); if (!m) return "no-menu"; m.children[7].querySelector("[role=button]").click(); return location.pathname; })()'
    & powershell -NoProfile -NoLogo -ExecutionPolicy Bypass -File $cdp -Script $nav | Out-Null
    Start-Sleep -Milliseconds 900
    & powershell -NoProfile -NoLogo -ExecutionPolicy Bypass -File $cdp -Script 'window.__VERGE_GLASS__.mount(true); "mounted"' | Out-Null
    Start-Sleep -Milliseconds 500
}
if ($Shot) {
    & powershell -NoProfile -NoLogo -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot "shot.ps1") -Out $Shot
}
