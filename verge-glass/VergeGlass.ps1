<#
.SYNOPSIS
    VergeGlass - semi-transparent theme plugin for Clash Verge Rev (2.5.x)

.DESCRIPTION
    Injects a "glass" theme + an in-app settings card into Clash Verge Rev
    without touching the application's source code or binaries.

    How it works:
      * launches Clash Verge with WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS
        (--remote-debugging-port) so the WebView2 page can be reached over CDP
      * injects src\verge-glass.css + src\verge-glass.js into the page
      * the injected script renders a settings card inside Settings page and
        persists user settings in localStorage (nothing written to verge.yaml
        unless -WriteCssInjection is used)

.PARAMETER Action
    install    copy plugin to %LOCALAPPDATA%\VergeGlass, register logon task,
               start Clash Verge with CDP, inject, then keep watching
    start      start Clash Verge with CDP, inject, keep watching (blocking)
    apply      one-shot inject into the already running app
    status     show app/plugin/theme state
    check      compare installed app with the latest GitHub release and probe
               the selectors the theme relies on
    update     fetch plugin files from the update manifest and re-inject
    uninstall  remove logon task, plugin files, restore modified app settings

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File VergeGlass.ps1 install
    powershell -ExecutionPolicy Bypass -File VergeGlass.ps1 status
    powershell -ExecutionPolicy Bypass -File VergeGlass.ps1 check
#>
[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [ValidateSet("install", "uninstall", "start", "apply", "status", "check", "update")]
    [string]$Action = "status",
    [string]$AppPath = "",
    [int]$Port = 9333,
    [switch]$RestartApp,
    [switch]$WriteCssInjection,
    [string]$UpdateUrl = "",
    [switch]$NoAutostart,
    [switch]$Quiet
)

$ErrorActionPreference = "Stop"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# ---------------------------------------------------------------- constants
$PluginRoot = $PSScriptRoot
$DataDir = Join-Path $env:LOCALAPPDATA "VergeGlass"
$ConfigPath = Join-Path $DataDir "config.json"
$LauncherPath = Join-Path $DataDir "VergeGlass.vbs"
$RunKey = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run"
$RunValueName = "VergeGlass"
$AppId = "io.github.clash-verge-rev.clash-verge-rev"
$RoamingDir = Join-Path $env:APPDATA $AppId
$VergeYaml = Join-Path $RoamingDir "verge.yaml"
$ManifestPath = Join-Path $PluginRoot "plugin.json"
$CssPath = Join-Path $PluginRoot "src\verge-glass.css"
$JsPath = Join-Path $PluginRoot "src\verge-glass.js"
$SupportedAppRange = ">=2.4.0 <2.7.0"

# ---------------------------------------------------------------- helpers
function Write-Log {
    param([string]$Message)
    $stamp = Get-Date -Format "HH:mm:ss"
    Write-Host "[$stamp] $Message"
}

function Write-Step {
    param([string]$Message)
    if (-not $Quiet) { Write-Host $Message }
}

function Get-PluginManifest {
    if (Test-Path $ManifestPath) {
        return (Get-Content $ManifestPath -Raw -Encoding UTF8 | ConvertFrom-Json)
    }
    return $null
}

function Get-PluginVersion {
    $m = Get-PluginManifest
    if ($m -and $m.version) { return [string]$m.version }
    return "0.0.0"
}

function Get-AppExe {
    if ($AppPath) {
        if (Test-Path $AppPath) { return (Resolve-Path $AppPath).Path }
        throw "AppPath not found: $AppPath"
    }
    $candidates = @(
        (Join-Path $env:ProgramFiles "Clash Verge\clash-verge.exe"),
        (Join-Path ${env:ProgramFiles(x86)} "Clash Verge\clash-verge.exe"),
        (Join-Path $env:LOCALAPPDATA "Programs\clash-verge\clash-verge.exe"),
        (Join-Path $env:LOCALAPPDATA "Programs\Clash Verge\clash-verge.exe")
    )
    foreach ($c in $candidates) {
        if ($c -and (Test-Path $c)) { return $c }
    }
    $keys = @(
        "HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*"
    )
    foreach ($k in $keys) {
        $items = Get-ItemProperty $k -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -like "Clash Verge*" -and $_.InstallLocation }
        foreach ($it in $items) {
            $exe = Join-Path ($it.InstallLocation.Trim('"')) "clash-verge.exe"
            if (Test-Path $exe) { return $exe }
        }
    }
    $proc = Get-Process clash-verge -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($proc -and $proc.Path) { return $proc.Path }
    throw "Clash Verge executable not found. Pass -AppPath."
}

function Get-AppVersion {
    param([string]$Exe)
    if (-not $Exe) { return "" }
    try { return (Get-Item $Exe).VersionInfo.FileVersion } catch { return "" }
}

function Get-AppRunning {
    return [bool](Get-Process clash-verge -ErrorAction SilentlyContinue)
}

function Get-CdpHttp {
    param([string]$Path)
    return (Invoke-WebRequest -Uri "http://127.0.0.1:$Port$Path" -UseBasicParsing -TimeoutSec 5).Content
}

function Get-CdpPageTarget {
    $raw = Get-CdpHttp "/json/list"
    $docs = ConvertFrom-Json $raw
    if ($docs -is [array] -and $docs.Count -eq 1 -and $docs[0] -is [array]) { $docs = $docs[0] }
    $pages = @()
    foreach ($d in $docs) { if ($d.type -eq "page" -and $d.webSocketDebuggerUrl) { $pages += $d } }
    if ($pages.Count -eq 0) { return $null }
    return $pages[0]
}

function Wait-Cdp {
    param([int]$TimeoutSec = 25)
    $deadline = (Get-Date).AddSeconds($TimeoutSec)
    while ((Get-Date) -lt $deadline) {
        try {
            $t = Get-CdpPageTarget
            if ($t) { return $t }
        } catch { }
        Start-Sleep -Milliseconds 700
    }
    return $null
}

# ---------------------------------------------------------------- CDP session
function New-CdpSession {
    param([string]$WsUrl, [int]$TimeoutSec = 20)
    $ws = New-Object System.Net.WebSockets.ClientWebSocket
    $ws.Options.KeepAliveInterval = [TimeSpan]::FromSeconds(5)
    $cts = New-Object System.Threading.CancellationTokenSource
    $cts.CancelAfter([TimeSpan]::FromSeconds($TimeoutSec))
    $ws.ConnectAsync([Uri]$WsUrl, $cts.Token).Wait($TimeoutSec * 1000) | Out-Null
    if ($ws.State -ne [System.Net.WebSockets.WebSocketState]::Open) { throw "websocket not open: $($ws.State)" }
    $sess = [pscustomobject]@{
        Ws          = $ws
        Cts         = $cts
        Id          = 0
        Buffer      = New-Object byte[] 8388608
        InjectionId = ""
    }
    return $sess
}

function Close-CdpSession {
    param($Session)
    if (-not $Session) { return }
    try { $Session.Ws.CloseAsync([System.Net.WebSockets.WebSocketCloseStatus]::NormalClosure, "done", [Threading.CancellationToken]::None).Wait(2000) | Out-Null } catch { }
    try { $Session.Ws.Dispose() } catch { }
    try { $Session.Cts.Dispose() } catch { }
}

function Send-Cdp {
    param($Session, [string]$Method, [hashtable]$Params = @{})
    $Session.Id = $Session.Id + 1
    $payload = @{ id = $Session.Id; method = $Method; params = $Params } | ConvertTo-Json -Depth 20 -Compress
    $bytes = [Text.Encoding]::UTF8.GetBytes($payload)
    $seg = New-Object 'System.ArraySegment[byte]' -ArgumentList @(, $bytes)
    $task = $Session.Ws.SendAsync($seg, [System.Net.WebSockets.WebSocketMessageType]::Text, $true, [Threading.CancellationToken]::None)
    if (-not $task.Wait(10000)) { throw "cdp send timeout" }
    return $Session.Id
}

function Receive-Cdp {
    param($Session, [int]$WaitId, [int]$TimeoutSec = 15)
    $deadline = (Get-Date).AddSeconds($TimeoutSec)
    while ((Get-Date) -lt $deadline) {
        $sb = New-Object Text.StringBuilder
        do {
            $seg = New-Object 'System.ArraySegment[byte]' -ArgumentList @(, $Session.Buffer)
            $task = $Session.Ws.ReceiveAsync($seg, [Threading.CancellationToken]::None)
            if (-not $task.Wait(($TimeoutSec * 1000))) { throw "cdp receive timeout" }
            $res = $task.Result
            [void]$sb.Append([Text.Encoding]::UTF8.GetString($Session.Buffer, 0, $res.Count))
        } while (-not $res.EndOfMessage)
        $obj = $sb.ToString() | ConvertFrom-Json
        if ($obj.id -eq $WaitId) { return $obj }
    }
    throw "cdp response timeout"
}

function Invoke-Cdp {
    param($Session, [string]$Method, [hashtable]$Params = @{})
    $id = Send-Cdp -Session $Session -Method $Method -Params $Params
    return (Receive-Cdp -Session $Session -WaitId $id)
}

function Invoke-CdpJs {
    param($Session, [string]$Expression, [int]$TimeoutSec = 20)
    $r = Invoke-Cdp -Session $Session -Method "Runtime.evaluate" -Params @{
        expression    = $Expression
        returnByValue = $true
        awaitPromise  = $true
    }
    if ($r.result -and $r.result.exceptionDetails) { throw ("js error: " + $r.result.exceptionDetails.text) }
    return $r
}

# ---------------------------------------------------------------- theme bits
function Get-WallpaperPath {
    try {
        $wp = (Get-ItemProperty "HKCU:\Control Panel\Desktop" -Name Wallpaper -ErrorAction SilentlyContinue).Wallpaper
        if ($wp -and (Test-Path $wp)) { return $wp }
    } catch { }
    $transcoded = Join-Path $env:APPDATA "Microsoft\Windows\Themes\TranscodedWallpaper"
    if (Test-Path $transcoded) { return $transcoded }
    return ""
}

function Get-WallpaperAssetUrl {
    $p = Get-WallpaperPath
    if (-not $p) { return "" }
    return "http://asset.localhost/" + [uri]::EscapeDataString($p)
}

function Build-InjectionSource {
    $css = [IO.File]::ReadAllText($CssPath, [Text.Encoding]::UTF8)
    $js = [IO.File]::ReadAllText($JsPath, [Text.Encoding]::UTF8)
    $exe = $null
    try { $exe = Get-AppExe } catch { }
    $hostObj = @{
        version    = (Get-PluginVersion)
        appVersion = (Get-AppVersion $exe)
        css        = $css
        wallpaper  = (Get-WallpaperAssetUrl)
        port       = $Port
    } | ConvertTo-Json -Depth 5 -Compress
    return "window.__VG_HOST__ = " + $hostObj + ";`n" + $js
}

function Enable-RemoteDebugEnv {
    $env:WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS = "--remote-debugging-port=$Port"
}

function Start-AppWithCdp {
    $exe = Get-AppExe
    Enable-RemoteDebugEnv
    $wd = Split-Path -Parent $exe
    Start-Process -FilePath $exe -WorkingDirectory $wd | Out-Null
    Write-Log "launched: $exe (CDP port $Port)"
}

function Stop-App {
    $p = Get-Process clash-verge -ErrorAction SilentlyContinue
    if ($p) {
        Write-Log "stopping Clash Verge ..."
        $p | Stop-Process -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 2
    }
}

function Start-AppAndShow {
    $exe = Get-AppExe
    Start-AppWithCdp
    Start-Sleep -Seconds 5
    if (-not (Test-CdpReady)) {
        # silent start / lightweight mode may keep the webview unmounted;
        # a second launch activates the window and creates it
        Start-Process -FilePath $exe -WorkingDirectory (Split-Path -Parent $exe) | Out-Null
        Start-Sleep -Seconds 4
    }
}

function Connect-CdpSession {
    $t = Wait-Cdp -TimeoutSec 12
    if (-not $t) { return $null }
    return (New-CdpSession -WsUrl $t.webSocketDebuggerUrl)
}

function Install-Injection {
    param($Session, [string]$Source)
    [void](Invoke-Cdp -Session $Session -Method "Page.enable")
    if ($Session.InjectionId) {
        try { [void](Invoke-Cdp -Session $Session -Method "Page.removeScriptToEvaluateOnNewDocument" -Params @{ identifier = $Session.InjectionId }) } catch { }
        $Session.InjectionId = ""
    }
    $add = Invoke-Cdp -Session $Session -Method "Page.addScriptToEvaluateOnNewDocument" -Params @{ source = $Source }
    if ($add.result -and $add.result.identifier) { $Session.InjectionId = [string]$add.result.identifier }
    # evaluate current document as well (page may already be loaded)
    $eval = Invoke-Cdp -Session $Session -Method "Runtime.evaluate" -Params @{
        expression    = $Source
        returnByValue = $true
        awaitPromise  = $true
    }
    return $eval
}

function Test-Injected {
    param($Session)
    $r = Invoke-CdpJs -Session $Session -Expression "!!(window.__VERGE_GLASS__ && window.__VERGE_GLASS__.version)" -TimeoutSec 8
    return [bool]$r.result.result.value
}

# ---------------------------------------------------------------- window effects
$script:winApiReady = $false
$script:appliedHwnd = [IntPtr]::Zero
$script:appliedAlpha = -1.0
$script:appliedDark = $null

function Ensure-WinApi {
    if ($script:winApiReady) { return }
    Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public class VGWin {
    [DllImport("user32.dll")] public static extern int GetWindowLong(IntPtr hWnd, int nIndex);
    [DllImport("user32.dll")] public static extern int SetWindowLong(IntPtr hWnd, int nIndex, int dwNewLong);
    [DllImport("user32.dll")] public static extern bool SetLayeredWindowAttributes(IntPtr hwnd, uint crKey, byte bAlpha, uint dwFlags);
    [DllImport("dwmapi.dll")] public static extern int DwmSetWindowAttribute(IntPtr hwnd, int attr, ref int value, int size);
    [DllImport("dwmapi.dll")] public static extern int DwmExtendFrameIntoClientArea(IntPtr hwnd, ref MARGINS m);
    [DllImport("user32.dll")] public static extern int SetWindowCompositionAttribute(IntPtr hwnd, ref WCADATA data);
    [StructLayout(LayoutKind.Sequential)] public struct MARGINS { public int cxLeftWidth, cxRightWidth, cyTopHeight, cyBottomHeight; }
    [StructLayout(LayoutKind.Sequential)] public struct ACCENTPOLICY { public int AccentState; public int AccentFlags; public uint GradientColor; public int AnimationId; }
    [StructLayout(LayoutKind.Sequential)] public struct WCADATA { public int Attribute; public IntPtr Data; public int SizeOfData; }
    public static void Accent(IntPtr h, int state, int flags, uint color) {
        ACCENTPOLICY p = new ACCENTPOLICY();
        p.AccentState = state; p.AccentFlags = flags; p.GradientColor = color; p.AnimationId = 0;
        IntPtr ptr = Marshal.AllocHGlobal(Marshal.SizeOf(p));
        Marshal.StructureToPtr(p, ptr, false);
        WCADATA d = new WCADATA();
        d.Attribute = 19; d.Data = ptr; d.SizeOfData = Marshal.SizeOf(p);
        SetWindowCompositionAttribute(h, ref d);
        Marshal.FreeHGlobal(ptr);
    }
}
"@
    $script:winApiReady = $true
}

function Get-AppHwnd {
    $p = Get-Process clash-verge -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowHandle -ne 0 } | Select-Object -First 1
    if (-not $p) { return [IntPtr]::Zero }
    return $p.MainWindowHandle
}

function Set-WindowAlpha {
    param([IntPtr]$Hwnd, [double]$Alpha)
    Ensure-WinApi
    $GWL_EXSTYLE = -20
    $WS_EX_LAYERED = 0x00080000
    $style = [VGWin]::GetWindowLong($Hwnd, $GWL_EXSTYLE)
    if ($Alpha -ge 0.995) {
        if (($style -band $WS_EX_LAYERED) -ne 0) {
            [void][VGWin]::SetWindowLong($Hwnd, $GWL_EXSTYLE, ($style -band (-bnot $WS_EX_LAYERED)))
            Write-Log "window transparency off"
        }
        return
    }
    if (($style -band $WS_EX_LAYERED) -eq 0) {
        [void][VGWin]::SetWindowLong($Hwnd, $GWL_EXSTYLE, ($style -bor $WS_EX_LAYERED))
    }
    $byteAlpha = [byte][math]::Round([math]::Max(0.05, [math]::Min(1.0, $Alpha)) * 255)
    [void][VGWin]::SetLayeredWindowAttributes($Hwnd, 0, $byteAlpha, 0x2)
}

function Set-TitlebarGlass {
    param([IntPtr]$Hwnd, [bool]$Dark, [bool]$Enabled)
    Ensure-WinApi
    $m = New-Object VGWin+MARGINS
    if ($Enabled) {
        $m.cxLeftWidth = 0; $m.cxRightWidth = 0; $m.cyTopHeight = 40; $m.cyBottomHeight = 0
    } else {
        $m.cxLeftWidth = 0; $m.cxRightWidth = 0; $m.cyTopHeight = 0; $m.cyBottomHeight = 0
    }
    try { [void][VGWin]::DwmExtendFrameIntoClientArea($Hwnd, [ref]$m) } catch { }
    # 注意：ACCENT_ENABLE_BLURBEHIND 会把模糊扩散到窗口非客户区，形成一圈半透明外框，
    # 所以这里只保留「扩展标题栏」让标题栏透明，不再叠加 accent 模糊。
    try { [VGWin]::Accent($Hwnd, 0, 0, 0) | Out-Null } catch { }
}

function Set-TitlebarDark {
    param([IntPtr]$Hwnd, [bool]$Dark)
    Ensure-WinApi
    $v = if ($Dark) { 1 } else { 0 }
    try { [void][VGWin]::DwmSetWindowAttribute($Hwnd, 20, [ref]$v, 4) } catch { }
}
# ---------------------------------------------------------------- app settings
function Set-AppAutoLaunch {
    param([bool]$Enabled)
    # prefer the app's own IPC when it is reachable over CDP
    if (Get-AppRunning) {
        $t = $null
        try { $t = Get-CdpPageTarget } catch { }
        if ($t) {
            $sess = $null
            try {
                $sess = New-CdpSession -WsUrl $t.webSocketDebuggerUrl
                $js = "window.__TAURI_INTERNALS__.invoke('patch_verge_config',{payload:{enable_auto_launch:$($Enabled.ToString().ToLower())}}).then(()=> 'ok')"
                $r = Invoke-CdpJs -Session $sess -Expression $js
                if ([string]$r.result.result.value -eq "ok") {
                    Write-Log "enable_auto_launch -> $Enabled (via app IPC)"
                    return $true
                }
            } catch {
                Write-Log "IPC patch failed: $($_.Exception.Message)"
            } finally {
                Close-CdpSession $sess
            }
        }
    }
    # fall back to editing verge.yaml while the app is not running
    if (-not (Test-Path $VergeYaml)) { return $false }
    if (Get-AppRunning) { Write-Log "app is running; skip verge.yaml edit"; return $false }
    Copy-Item $VergeYaml "$VergeYaml.vgbak" -Force
    $text = [IO.File]::ReadAllText($VergeYaml, [Text.Encoding]::UTF8)
    $pattern = "(?m)^enable_auto_launch:.*$"
    $replacement = "enable_auto_launch: " + $Enabled.ToString().ToLower()
    $new = [regex]::Replace($text, $pattern, $replacement)
    if ($new -ne $text) {
        [IO.File]::WriteAllText($VergeYaml, $new, (New-Object Text.UTF8Encoding $false))
        Write-Log "enable_auto_launch -> $Enabled (verge.yaml)"
        return $true
    }
    return $false
}

function Get-AppAutoLaunch {
    if (Test-Path $VergeYaml) {
        $m = Select-String -Path $VergeYaml -Pattern "^enable_auto_launch:\s*(\S+)" | Select-Object -First 1
        if ($m) { return ($m.Matches[0].Groups[1].Value -eq "true") }
    }
    return $null
}

function Write-ThemeToApp {
    param($Session)
    $expr = @'
(async () => {
  const css = window.__VG_HOST__.css;
  const s = window.__VERGE_GLASS__.settings;
  const wall = s.bg === "none" ? "none" : (s.bg === "custom" && s.customWall ? 'url("' + s.customWall + '")' : 'url("' + window.__VG_HOST__.wallpaper + '")');
  const extra = "html:root{--vg-alpha:" + s.alpha + ";--vg-blur:" + s.blur + "px;--vg-wallpaper:" + wall +
    ";--vg-wall-opacity:" + s.wallOpacity + ";--vg-wall-blur:" + s.wallBlur + "px;--vg-veil:" + s.veil + ";}";
  const cfg = await window.__TAURI_INTERNALS__.invoke("get_verge_config");
  const theme = (cfg && cfg.theme_setting) || {};
  theme.css_injection = css + "\n" + extra;
  await window.__TAURI_INTERNALS__.invoke("patch_verge_config", { payload: { theme_setting: theme } });
  return "written";
})()
'@
    $r = Invoke-CdpJs -Session $Session -Expression $expr -TimeoutSec 25
    return [string]$r.result.result.value
}

# ---------------------------------------------------------------- probes
function Get-ProbeResults {
    param($Session)
    $expr = @'
(() => {
  const probes = {
    "layout-root": ".MuiPaper-root.windows.layout",
    "sidebar": ".layout-content__left",
    "content": ".the-content",
    "base-container": ".base-container",
    "settings-grid": ".the-content .base-content .MuiGrid-container",
    "menu": "ul.the-menu"
  };
  const out = {};
  for (const k in probes) out[k] = !!document.querySelector(probes[k]);
  out.version = (window.__VG_HOST__ && window.__VG_HOST__.appVersion) || "";
  out.plugin = (window.__VERGE_GLASS__ && window.__VERGE_GLASS__.version) || "";
  out.tone = document.documentElement.getAttribute("data-vg-tone") || "";
  return JSON.stringify(out);
})()
'@
    $r = Invoke-CdpJs -Session $Session -Expression $expr
    return ($r.result.result.value | ConvertFrom-Json)
}

# ---------------------------------------------------------------- actions
function Start-WatcherIfNeeded {
    $existing = Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -ErrorAction SilentlyContinue |
        Where-Object { $_.CommandLine -and $_.CommandLine -match 'VergeGlass\.ps1"?\s+start' }
    if ($existing) { return $false }
    if (-not (Test-Path $LauncherPath)) { return $false }
    Start-Process -FilePath "wscript.exe" -ArgumentList ("//B """ + $LauncherPath + """") | Out-Null
    return $true
}

function Copy-Changed {
    param([string]$Source, [string]$Dest)
    if ([IO.File]::Exists($Dest)) {
        try {
            if ((Get-Item $Source).Length -eq (Get-Item $Dest).Length) {
                $a = (Get-FileHash $Source -Algorithm SHA256).Hash
                $b = (Get-FileHash $Dest -Algorithm SHA256).Hash
                if ($a -eq $b) { return $false }
            }
        } catch { }
    }
    [IO.File]::Copy($Source, $Dest, $true)
    return $true
}

function Persist-IfPending {
    param($Session)
    $flag = Join-Path $DataDir "persist.pending"
    if (-not (Test-Path $flag)) { return }
    try {
        $backupPath = Join-Path $DataDir "backup-css.txt"
        if (-not (Test-Path $backupPath)) {
            $prevExpr = '(async () => { const c = await window.__TAURI_INTERNALS__.invoke("get_verge_config"); return ((c && c.theme_setting && c.theme_setting.css_injection) || ""); })()'
            $prev = Invoke-CdpJs -Session $Session -Expression $prevExpr -TimeoutSec 12
            $prevCss = [string]$prev.result.result.value
            if ($prevCss -and $prevCss -notmatch "Verge Glass") {
                [IO.File]::WriteAllText($backupPath, $prevCss, (New-Object Text.UTF8Encoding $false))
            }
        }
        [void](Write-ThemeToApp -Session $Session)
        Remove-Item $flag -Force -ErrorAction SilentlyContinue
        Write-Log "theme persisted into css_injection (applies on next restart even without the plugin)"
    } catch {
        Write-Log "persist skipped: $($_.Exception.Message)"
    }
}

function Invoke-Install {
    Write-Log "installing VergeGlass $((Get-PluginVersion))"
    [IO.Directory]::CreateDirectory($DataDir) | Out-Null
    [IO.Directory]::CreateDirectory((Join-Path $DataDir "src")) | Out-Null
    [IO.File]::Copy($CssPath, (Join-Path $DataDir "src\verge-glass.css"), $true)
    [IO.File]::Copy($JsPath, (Join-Path $DataDir "src\verge-glass.js"), $true)
    [IO.File]::Copy($ManifestPath, (Join-Path $DataDir "plugin.json"), $true)
    [IO.File]::Copy((Join-Path $PluginRoot "VergeGlass.ps1"), (Join-Path $DataDir "VergeGlass.ps1"), $true)
    $iconSrc = Join-Path $PluginRoot "assets\clash-verge.ico"
    if (Test-Path $iconSrc) { [void](Copy-Changed $iconSrc (Join-Path $DataDir "clash-verge.ico")) }

    $vbs = @"
Set sh = CreateObject("WScript.Shell")
sh.Run "powershell.exe -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File ""$DataDir\VergeGlass.ps1"" start", 0, False
"@
    [IO.File]::WriteAllText($LauncherPath, $vbs, (New-Object Text.ASCIIEncoding))

    if (-not $NoAutostart) {
        Set-ItemProperty -Path $RunKey -Name $RunValueName -Value ("wscript.exe //B """ + $LauncherPath + """")
        Write-Log "logon entry registered: HKCU\...\Run\$RunValueName"
    }

    $prevAutoLaunch = Get-AppAutoLaunch
    $cfg = [pscustomobject]@{
        port              = $Port
        updateUrl         = $UpdateUrl
        appAutoLaunchPrev = $prevAutoLaunch
        installedAt       = (Get-Date).ToString("s")
    }
    [IO.File]::WriteAllText($ConfigPath, ($cfg | ConvertTo-Json), (New-Object Text.UTF8Encoding $false))

    # Clash Verge must be started by the launcher to keep CDP available
    if ($prevAutoLaunch -eq $true -and -not $KeepAppAutoLaunch) {
        Write-Log "disabling Clash Verge's own auto launch (launcher takes over)"
        [void](Set-AppAutoLaunch -Enabled $false)
    }

    # 应用统一由守护进程启动并注入（install 不再自己连 CDP，流程少一步）
    if (-not (Get-AppRunning)) {
        Start-AppWithCdp
        Start-Sleep -Seconds 3
    } elseif (-not (Test-CdpReady)) {
        Write-Log "Clash Verge is running without CDP; restarting once"
        Stop-App
        Start-AppWithCdp
        Start-Sleep -Seconds 3
    }

    $shortcut = Join-Path ([Environment]::GetFolderPath("Programs")) "Clash Verge (Verge Glass).lnk"
    try {
        $ws = New-Object -ComObject WScript.Shell
        $lnk = $ws.CreateShortcut($shortcut)
        $lnk.TargetPath = "wscript.exe"
        $lnk.Arguments = "//B """ + $LauncherPath + """"
        $lnk.WorkingDirectory = $DataDir
        $lnk.Description = "Launch Clash Verge with Verge Glass theme"
        $iconPath = Join-Path $DataDir "clash-verge.ico"
        if (Test-Path $iconPath) { $lnk.IconLocation = $iconPath + ",0" }
        $lnk.Save()
        Write-Log "start menu shortcut: $shortcut"
    } catch {
        Write-Log "shortcut creation failed: $($_.Exception.Message)"
    }

    if (Start-WatcherIfNeeded) { Write-Log "background watcher started" }
    else { Write-Log "watcher already running" }

    # 主题写入交给守护进程（它已经有 CDP 会话），安装不再阻塞等待
    if (-not $NoPersistTheme) {
        [IO.File]::WriteAllText((Join-Path $DataDir "persist.pending"), "1")
        Write-Log "theme will be persisted once the app window is ready"
    }
    Write-Log "installed. Open Clash Verge -> Settings (bottom of page) for the theme card."
}

function Test-CdpReady {
    try {
        $t = Get-CdpPageTarget
        return [bool]$t
    } catch {
        return $false
    }
}

function Invoke-Start {
    if (-not (Get-AppRunning)) {
        Start-AppAndShow
    } elseif (-not (Test-CdpReady)) {
        if ($RestartApp) {
            Write-Log "restarting Clash Verge to enable CDP"
            Stop-App
            Start-AppAndShow
        } else {
            Write-Log "waiting for the WebView2 window (CDP) ..."
            [void](Wait-Cdp -TimeoutSec 15)
            if (-not (Test-CdpReady)) {
                Write-Log "window not created yet; watcher keeps waiting in background"
            }
        }
    }
    $source = Build-InjectionSource
    $sess = Connect-CdpSession
    if (-not $sess) { throw "could not connect to WebView2 (CDP port $Port)" }
    try {
        [void](Install-Injection -Session $sess -Source $source)
        Persist-IfPending -Session $sess
        if ($WriteCssInjection) {
            Start-Sleep -Milliseconds 1200
            [void](Write-ThemeToApp -Session $sess)
            Write-Log "theme written to Clash Verge setting (css_injection)"
        }
    } finally {
        Close-CdpSession $sess
    }
    Write-Log "injected. Watching for app restarts / page reloads (Ctrl+C to stop; theme stays applied until app exits)."
    $sess = $null
    $pluginVersion = Get-PluginVersion
    while ($true) {
        try {
            if (-not (Get-AppRunning)) {
                Write-Log "Clash Verge exited; watcher stopping (theme is re-applied on next launch through the launcher)"
                break
            }
            if (-not $sess -or $sess.Ws.State -ne [System.Net.WebSockets.WebSocketState]::Open) {
                if ($sess) { Close-CdpSession $sess }
                $sess = Connect-CdpSession
                if (-not $sess) { Start-Sleep -Seconds 5; continue }
            }
            $nowVersion = Get-PluginVersion
            if ($nowVersion -ne $pluginVersion) {
                Write-Log "plugin updated on disk: v$pluginVersion -> v$nowVersion (hot reload)"
                $pluginVersion = $nowVersion
                [void](Install-Injection -Session $sess -Source (Build-InjectionSource))
                Persist-IfPending -Session $sess
                try { [void](Invoke-CdpJs -Session $sess -Expression "location.reload()" -TimeoutSec 5) } catch { }
                Start-Sleep -Seconds 3
                continue
            }
            # 读取页面状态：是否已注入 / 窗口透视 alpha / 明暗基调
            $stateJson = $null
            try {
                $r = Invoke-CdpJs -Session $sess -Expression "JSON.stringify({i:!!(window.__VERGE_GLASS__&&window.__VERGE_GLASS__.version),v:(window.__VERGE_GLASS__&&window.__VERGE_GLASS__.version)||'',a:(window.__VERGE_GLASS__&&window.__VERGE_GLASS__.windowAlpha)||1,t:document.documentElement.getAttribute('data-vg-tone')||''})" -TimeoutSec 8
                $stateJson = [string]$r.result.result.value
            } catch { }
            if (-not $stateJson -or $stateJson -eq "") {
                if (-not (Test-Injected -Session $sess)) {
                    Write-Log "injecting into new page"
                    [void](Install-Injection -Session $sess -Source (Build-InjectionSource))
                }
            } else {
                $st = ConvertFrom-Json $stateJson
                if (-not $st.i) {
                    Write-Log "injecting into new page"
                    [void](Install-Injection -Session $sess -Source (Build-InjectionSource))
                } elseif ($st.v -and $st.v -ne $pluginVersion) {
                    Write-Log "page runs v$($st.v), plugin is v$pluginVersion -> reloading"
                    [void](Install-Injection -Session $sess -Source (Build-InjectionSource))
                    try { [void](Invoke-CdpJs -Session $sess -Expression "location.reload()" -TimeoutSec 5) } catch { }
                    Start-Sleep -Seconds 3
                    continue
                }
                $hwnd = Get-AppHwnd
                if ($hwnd -ne [IntPtr]::Zero) {
                    $alpha = [double]$st.a
                    $dark = ($st.t -eq "dark")
                    if ($hwnd -ne $script:appliedHwnd -or [math]::Abs($alpha - $script:appliedAlpha) -gt 0.004) {
                        Set-WindowAlpha -Hwnd $hwnd -Alpha $alpha
                        Set-TitlebarGlass -Hwnd $hwnd -Dark $dark -Enabled ($alpha -lt 0.995)
                        $script:appliedHwnd = $hwnd
                        $script:appliedAlpha = $alpha
                        $script:appliedDark = $dark
                    }
                    if ($null -eq $script:appliedDark -or $dark -ne $script:appliedDark) {
                        Set-TitlebarDark -Hwnd $hwnd -Dark $dark
                        Set-TitlebarGlass -Hwnd $hwnd -Dark $dark -Enabled ($alpha -lt 0.995)
                        $script:appliedDark = $dark
                    }
                }
            }
            Start-Sleep -Seconds 1
        } catch {
            if ($sess) { try { Close-CdpSession $sess } catch { } }
            $sess = $null
            Start-Sleep -Seconds 5
        }
    }
}

function Sync-WindowEffects {
    param($Session)
    try {
        $r = Invoke-CdpJs -Session $Session -Expression "JSON.stringify({a:(window.__VERGE_GLASS__&&window.__VERGE_GLASS__.windowAlpha)||1,t:document.documentElement.getAttribute('data-vg-tone')||''})" -TimeoutSec 8
        $st = [string]$r.result.result.value | ConvertFrom-Json
        $h = Get-AppHwnd
        if ($h -ne [IntPtr]::Zero) {
            $alpha = [double]$st.a
            $dark = ($st.t -eq "dark")
            Set-WindowAlpha -Hwnd $h -Alpha $alpha
            Set-TitlebarDark -Hwnd $h -Dark $dark
            Set-TitlebarGlass -Hwnd $h -Dark $dark -Enabled ($alpha -lt 0.995)
            $script:appliedHwnd = $h
            $script:appliedAlpha = $alpha
            $script:appliedDark = $dark
        }
    } catch { }
}

function Invoke-Apply {
    $sess = Connect-CdpSession
    if (-not $sess) { throw "no CDP target; start the app through VergeGlass.ps1 start" }
    try {
        [void](Install-Injection -Session $sess -Source (Build-InjectionSource))
        Sync-WindowEffects -Session $sess
        Write-Log "injected into running app"
    } finally {
        Close-CdpSession $sess
    }
}

function Invoke-Status {
    $exe = $null
    try { $exe = Get-AppExe } catch { }
    Write-Output "VergeGlass plugin : v$(Get-PluginVersion)"
    Write-Output "Clash Verge exe   : $exe"
    Write-Output "Clash Verge vers  : $(Get-AppVersion $exe)"
    Write-Output "app running       : $(Get-AppRunning)"
    Write-Output "CDP reachable     : $(Test-CdpReady)"
    $run = (Get-ItemProperty $RunKey -ErrorAction SilentlyContinue).$RunValueName
    Write-Output "logon entry       : $([bool]$run)"
    Write-Output "app auto launch   : $(Get-AppAutoLaunch)"
    if (Test-CdpReady) {
        $sess = Connect-CdpSession
        if ($sess) {
            try {
                $p = Get-ProbeResults -Session $sess
                Write-Output "injected version  : $($p.plugin)"
                Write-Output "detected tone     : $($p.tone)"
                $bad = @()
                foreach ($k in @("layout-root", "sidebar", "content", "base-container", "settings-grid", "menu")) {
                    if (-not $p.$k) { $bad += $k }
                }
                if ($bad.Count -eq 0) { Write-Output "selector probes   : all OK" }
                else { Write-Output ("selector probes   : MISSING " + ($bad -join ", ")) }
            } finally {
                Close-CdpSession $sess
            }
        }
    }
}

function Invoke-Check {
    Write-Output "== VergeGlass compatibility check =="
    $exe = $null
    try { $exe = Get-AppExe } catch { }
    $localApp = Get-AppVersion $exe
    Write-Output ("installed app      : " + $localApp)
    $release = $null
    try {
        $api = "https://api.github.com/repos/clash-verge-rev/clash-verge-rev/releases/latest"
        $release = Invoke-RestMethod -Uri $api -Headers @{ "User-Agent" = "VergeGlass" } -TimeoutSec 20
        Write-Output ("latest release     : " + $release.tag_name + "  (" + $release.published_at + ")")
        Write-Output ("release url        : " + $release.html_url)
    } catch {
        Write-Output ("latest release     : query failed - " + $_.Exception.Message)
    }
    if ($release -and $localApp) {
        $latest = $release.tag_name.TrimStart("v")
        if ($latest -ne $localApp) { Write-Output "=> app is NOT the latest release; consider updating Clash Verge" }
        else { Write-Output "=> app is up to date" }
    }
    $cfg = $null
    if (Test-Path $ConfigPath) { try { $cfg = Get-Content $ConfigPath -Raw | ConvertFrom-Json } catch { } }
    $url = if ($UpdateUrl) { $UpdateUrl } elseif ($cfg -and $cfg.updateUrl) { $cfg.updateUrl } else { "" }
    Write-Output ("plugin installed   : v" + (Get-PluginVersion) + "  (supported app: " + $SupportedAppRange + ")")
    if ($url) {
        try {
            $m = Invoke-RestMethod -Uri $url -Headers @{ "User-Agent" = "VergeGlass" } -TimeoutSec 20
            Write-Output ("plugin upstream    : v" + $m.version)
            if ([version]($m.version) -gt [version](Get-PluginVersion)) { Write-Output "=> plugin update available: run VergeGlass.ps1 update" }
            else { Write-Output "=> plugin is up to date" }
        } catch {
            Write-Output ("plugin upstream    : query failed - " + $_.Exception.Message)
        }
    } else {
        Write-Output "plugin upstream    : no UpdateUrl configured (see README, section 'Updating with new releases')"
    }
    if (Test-CdpReady) {
        $sess = Connect-CdpSession
        if ($sess) {
            try {
                $p = Get-ProbeResults -Session $sess
                $bad = @()
                foreach ($k in @("layout-root", "sidebar", "content", "base-container", "settings-grid", "menu")) {
                    if (-not $p.$k) { $bad += $k }
                }
                if ($bad.Count -eq 0) { Write-Output "selector probes    : all OK - the theme can be applied to this build" }
                else { Write-Output ("selector probes    : MISSING " + ($bad -join ", ") + " - the app layout changed, update src\verge-glass.css") }
            } finally {
                Close-CdpSession $sess
            }
        }
    } else {
        Write-Output "selector probes    : skipped (app not reachable over CDP)"
    }
}

function Invoke-Update {
    $cfg = $null
    if (Test-Path $ConfigPath) { try { $cfg = Get-Content $ConfigPath -Raw | ConvertFrom-Json } catch { } }
    $url = if ($UpdateUrl) { $UpdateUrl } elseif ($cfg -and $cfg.updateUrl) { $cfg.updateUrl } else { "" }
    if (-not $url) { throw "no UpdateUrl. Pass -UpdateUrl <url to plugin.json> or set it during install." }
    Write-Log "fetching manifest: $url"
    $rawManifest = (Invoke-WebRequest -Uri $url -UseBasicParsing -Headers @{ "User-Agent" = "VergeGlass" } -TimeoutSec 30).Content
    $m = ConvertFrom-Json $rawManifest
    $local = Get-PluginVersion
    if ([version]($m.version) -le [version]$local) {
        Write-Log "already up to date (local v$local, upstream v$($m.version))"
        return
    }
    $base = $url.Substring(0, $url.LastIndexOf("/") + 1)
    $files = $m.files
    if (-not $files) { throw "manifest has no 'files' section" }
    New-Item -ItemType Directory -Force -Path (Join-Path $DataDir "backup") | Out-Null
    foreach ($name in $files.PSObject.Properties.Name) {
        $rel = [string]$files.$name
        $target = Join-Path $PluginRoot $name
        if (Test-Path $target) { Copy-Item $target (Join-Path $DataDir ("backup\" + $name.Replace("/", "_"))) -Force }
        $fileUrl = if ($rel -match "^https?://") { $rel } else { $base + $rel }
        Write-Log "download $fileUrl"
        $tmp = "$target.download"
        Invoke-WebRequest -Uri $fileUrl -OutFile $tmp -UseBasicParsing -TimeoutSec 60 | Out-Null
        Move-Item $tmp $target -Force
    }
    [IO.File]::WriteAllText($ManifestPath, $rawManifest, (New-Object Text.UTF8Encoding $false))
    if ($PluginRoot -ne $DataDir) {
        Copy-Item $ManifestPath (Join-Path $DataDir "plugin.json") -Force
        Copy-Item $CssPath (Join-Path $DataDir "src\verge-glass.css") -Force
        Copy-Item $JsPath (Join-Path $DataDir "src\verge-glass.js") -Force
    }
    Write-Log "plugin updated to v$($m.version); re-injecting"
    if (Test-CdpReady) {
        $sess = Connect-CdpSession
        if ($sess) {
            try {
                Invoke-CdpJs -Session $sess -Expression "location.reload()" -TimeoutSec 5 | Out-Null
            } catch { }
            Start-Sleep -Seconds 2
            Close-CdpSession $sess
            $sess = Connect-CdpSession
            if ($sess) {
                try { [void](Install-Injection -Session $sess -Source (Build-InjectionSource)) } finally { Close-CdpSession $sess }
            }
        }
    }
    Write-Log "done"
}

function Invoke-Uninstall {
    Write-Log "uninstalling"
    if (Test-Path $RunKey) {
        Remove-ItemProperty -Path $RunKey -Name $RunValueName -ErrorAction SilentlyContinue
    }
    $watchers = Get-CimInstance Win32_Process -Filter "Name='powershell.exe' OR Name='wscript.exe'" -ErrorAction SilentlyContinue |
        Where-Object { $_.CommandLine -and $_.CommandLine -match 'VergeGlass\.ps1"?\s+start' -and $_.ProcessId -ne $PID }
    foreach ($w in $watchers) { Stop-Process -Id $w.ProcessId -Force -ErrorAction SilentlyContinue }
    $cfg = $null
    if (Test-Path $ConfigPath) { try { $cfg = Get-Content $ConfigPath -Raw | ConvertFrom-Json } catch { } }
    if ($cfg -and $cfg.appAutoLaunchPrev -eq $true) {
        Write-Log "restoring Clash Verge auto launch"
        [void](Set-AppAutoLaunch -Enabled $true)
    }
    # 还原安装前的 css_injection（App 正在运行且能连 CDP 时）
    $backupPath = Join-Path $DataDir "backup-css.txt"
    if ((Test-Path $backupPath) -and (Get-AppRunning)) {
        $sess = $null
        for ($i = 0; $i -lt 10 -and -not $sess; $i++) {
            $sess = Connect-CdpSession
            if (-not $sess) { Start-Sleep -Milliseconds 700 }
        }
        if ($sess) {
            try {
                $prevCss = [IO.File]::ReadAllText($backupPath, [Text.Encoding]::UTF8)
                $json = ConvertTo-Json -InputObject $prevCss -Compress
                $expr = '(async () => { const c = await window.__TAURI_INTERNALS__.invoke("get_verge_config"); const t = (c && c.theme_setting) || {}; t.css_injection = ' + $json + '; await window.__TAURI_INTERNALS__.invoke("patch_verge_config", { payload: { theme_setting: t } }); return "restored"; })()'
                [void](Invoke-CdpJs -Session $sess -Expression $expr -TimeoutSec 20)
                Write-Log "previous css_injection restored"
            } catch {
                Write-Log "css_injection restore failed: $($_.Exception.Message)"
            } finally {
                Close-CdpSession $sess
            }
        }
    } elseif (Test-Path $VergeYaml) {
        $hasTheme = Select-String -Path $VergeYaml -Pattern "vg-base|verge-glass" -Quiet
        if ($hasTheme) { Write-Log "note: css_injection left in verge.yaml (App was closed); clear it in Settings -> Theme -> CSS" }
    }
    $shortcut = Join-Path ([Environment]::GetFolderPath("Programs")) "Clash Verge (Verge Glass).lnk"
    if (Test-Path $shortcut) { Remove-Item $shortcut -Force -ErrorAction SilentlyContinue }
    if ([IO.Directory]::Exists($DataDir)) { [IO.Directory]::Delete($DataDir, $true) }
    Write-Log "uninstalled (logon entry removed)"
}

# ---------------------------------------------------------------- main
switch ($Action) {
    "install" { Invoke-Install }
    "start" { Invoke-Start }
    "apply" { Invoke-Apply }
    "status" { Invoke-Status }
    "check" { Invoke-Check }
    "update" { Invoke-Update }
    "uninstall" { Invoke-Uninstall }
}
