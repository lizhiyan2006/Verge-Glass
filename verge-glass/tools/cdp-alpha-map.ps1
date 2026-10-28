param(
    [string]$Expr = "",
    [string]$ExprFile = "",
    [string]$Out = ""
)
$ErrorActionPreference = 'Stop'
if ($ExprFile) { $Expr = [IO.File]::ReadAllText((Resolve-Path $ExprFile), [Text.Encoding]::UTF8) }
Add-Type -AssemblyName System.Drawing
$base = "http://127.0.0.1:9333"
$docs = ConvertFrom-Json (Invoke-WebRequest -Uri "$base/json/list" -UseBasicParsing -TimeoutSec 10).Content
if ($docs -is [array] -and $docs.Count -eq 1 -and $docs[0] -is [array]) { $docs = $docs[0] }
$target = $null; foreach ($d in $docs) { if ($d.type -eq "page") { $target = $d; break } }
$ws = New-Object System.Net.WebSockets.ClientWebSocket
$cts = New-Object System.Threading.CancellationTokenSource
$cts.CancelAfter([TimeSpan]::FromSeconds(90))
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
Send-Cdp 'Runtime.enable' @{} | Out-Null
Send-Cdp 'Page.enable' @{} | Out-Null
if ($Expr) {
    $id = Send-Cdp 'Runtime.evaluate' @{ expression = $Expr; returnByValue = $true; awaitPromise = $true }
    $r = Recv $id
    if ($r.result.exceptionDetails) { throw ($r.result.exceptionDetails | ConvertTo-Json -Depth 8) }
    "eval: " + ($r.result.result.value | Out-String).Trim()
    Start-Sleep -Milliseconds 600
}
if ($Out) {
    $id = Send-Cdp 'Page.captureScreenshot' @{ format = 'png'; fromSurface = $true }
    $resp = Recv $id
    [IO.File]::WriteAllBytes($Out, [Convert]::FromBase64String($resp.result.data))
}
try { $ws.CloseAsync([System.Net.WebSockets.WebSocketCloseStatus]::NormalClosure, 'done', [Threading.CancellationToken]::None).Wait(3000) | Out-Null } catch { }
if ($Out) {
    $bmp = [System.Drawing.Bitmap]::FromFile((Resolve-Path $Out))
    "image $($bmp.Width)x$($bmp.Height)"
    # ASCII map of the top-left 60x60 px: '.' transparent, '#' opaque, '+' semi
    $step = 1
    for ($y = 0; $y -lt 60; $y += 2) {
        $line = ''
        for ($x = 0; $x -lt 120; $x += 2) {
            $px = $bmp.GetPixel($x, $y)
            if ($px.A -eq 0) { $line += '.' }
            elseif ($px.A -eq 255) { $line += '#' }
            else { $line += '+' }
        }
        "{0,3} {1}" -f $y, $line
    }
    $bmp.Dispose()
}
