param(
    [Parameter(Mandatory = $true)][string]$CssFile,
    [string]$Out = "",
    [string]$JsFile = "",
    [switch]$AlphaMap
)
$ErrorActionPreference = 'Stop'
$base = "http://127.0.0.1:9333"
$docs = ConvertFrom-Json (Invoke-WebRequest -Uri "$base/json/list" -UseBasicParsing -TimeoutSec 10).Content
if ($docs -is [array] -and $docs.Count -eq 1 -and $docs[0] -is [array]) { $docs = $docs[0] }
$target = $null; foreach ($d in $docs) { if ($d.type -eq "page") { $target = $d; break } }
$ws = New-Object System.Net.WebSockets.ClientWebSocket
$cts = New-Object System.Threading.CancellationTokenSource
$cts.CancelAfter([TimeSpan]::FromSeconds(120))
$ws.ConnectAsync([Uri]$target.webSocketDebuggerUrl, $cts.Token).Wait(15000) | Out-Null
$script:msgId = 0
function Send-Cdp([string]$method, [hashtable]$params) {
    $script:msgId++
    $p = @{ id = $script:msgId; method = $method; params = $params } | ConvertTo-Json -Depth 20 -Compress
    $b = [Text.Encoding]::UTF8.GetBytes($p)
    $seg = New-Object 'System.ArraySegment[byte]' -ArgumentList @(,$b)
    $ws.SendAsync($seg, [System.Net.WebSockets.WebSocketMessageType]::Text, $true, $cts.Token).Wait(15000) | Out-Null
    return $script:msgId
}
function Recv([int]$id) {
    while ($true) {
        $buf = New-Object byte[] 8388608
        $sb = New-Object Text.StringBuilder
        do {
            $seg = New-Object 'System.ArraySegment[byte]' -ArgumentList @(,$buf)
            $t = $ws.ReceiveAsync($seg, $cts.Token); if (-not $t.Wait(60000)) { throw "timeout" }
            $r = $t.Result; [void]$sb.Append([Text.Encoding]::UTF8.GetString($buf, 0, $r.Count))
        } while (-not $r.EndOfMessage)
        $o = $sb.ToString() | ConvertFrom-Json
        if ($o.id -eq $id) { return $o }
    }
}
function Eval([string]$e) {
    $id = Send-Cdp 'Runtime.evaluate' @{ expression = $e; returnByValue = $true; awaitPromise = $true }
    $r = Recv $id
    if ($r.result.exceptionDetails) { return 'ERR: ' + ($r.result.exceptionDetails.exception.description) }
    return $r.result.result.value
}
Send-Cdp 'Runtime.enable' @{} | Out-Null
Send-Cdp 'Page.enable' @{} | Out-Null

$cssB64 = [Convert]::ToBase64String([IO.File]::ReadAllBytes((Resolve-Path $CssFile)))
if ($JsFile) {
    $jsB64 = [Convert]::ToBase64String([IO.File]::ReadAllBytes((Resolve-Path $JsFile)))
    $pushJs = @"
(function(){
  var bin = atob('$jsB64');
  var bytes = new Uint8Array(bin.length);
  for (var i = 0; i < bin.length; i++) bytes[i] = bin.charCodeAt(i);
  var js = new TextDecoder('utf-8').decode(bytes);
  window.__VERGE_GLASS__ = null;
  window.__VG_BOOT_SCHEDULED__ = false;
  (0, eval)(js);
  return 'js pushed';
})()
"@
    "js: " + (Eval $pushJs)
    Start-Sleep -Milliseconds 600
}
$push = @"
(function(){
  var bin = atob('$cssB64');
  var bytes = new Uint8Array(bin.length);
  for (var i = 0; i < bin.length; i++) bytes[i] = bin.charCodeAt(i);
  var css = new TextDecoder('utf-8').decode(bytes);
  window.__VG_HOST__ = window.__VG_HOST__ || {};
  window.__VG_HOST__.css = css;
  var el = document.getElementById('verge-glass');
  if (!el) return 'no style element';
  el.textContent = css;
  var t = document.getElementById('vg-try'); if (t) t.remove();
  return 'pushed ' + css.length + ' chars';
})()
"@
"css: " + (Eval $push)
Start-Sleep -Milliseconds 800
"state: " + (Eval "JSON.stringify({tone:document.documentElement.getAttribute('data-vg-tone'),clip:getComputedStyle(document.documentElement).clipPath,veil:getComputedStyle(document.body,'::after').backgroundColor,radius:getComputedStyle(document.documentElement).getPropertyValue('--vg-window-radius'),wallOp:document.documentElement.style.getPropertyValue('--vg-wall-opacity')})")

if ($Out) {
    $id = Send-Cdp 'Page.captureScreenshot' @{ format = 'png'; fromSurface = $true }
    $resp = Recv $id
    [IO.File]::WriteAllBytes($Out, [Convert]::FromBase64String($resp.result.data))
    if ($AlphaMap) {
        Add-Type -AssemblyName System.Drawing
        $bmp = [System.Drawing.Bitmap]::FromFile((Resolve-Path $Out))
        "image $($bmp.Width)x$($bmp.Height)"
        for ($y = 0; $y -lt 60; $y += 2) {
            $line = ''
            for ($x = 0; $x -lt 120; $x += 2) {
                $px = $bmp.GetPixel($x, $y)
                if ($px.A -eq 0) { $line += '.' } elseif ($px.A -eq 255) { $line += '#' } else { $line += '+' }
            }
            "{0,3} {1}" -f $y, $line
        }
        $bmp.Dispose()
    }
}
try { $ws.CloseAsync([System.Net.WebSockets.WebSocketCloseStatus]::NormalClosure, 'done', [Threading.CancellationToken]::None).Wait(3000) | Out-Null } catch { }
