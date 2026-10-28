param(
    [Parameter(Mandatory = $true)][string]$Out,
    [int]$Port = 9333,
    [int]$Width = 0,
    [int]$Height = 0
)
$ErrorActionPreference = 'Stop'
$base = "http://127.0.0.1:$Port"
$raw = (Invoke-WebRequest -Uri "$base/json/list" -UseBasicParsing -TimeoutSec 10).Content
$docs = ConvertFrom-Json $raw
if ($docs -is [array] -and $docs.Count -eq 1 -and $docs[0] -is [array]) { $docs = $docs[0] }
$target = $null
foreach ($d in $docs) { if ($d.type -eq "page") { $target = $d; break } }
if (-not $target) { throw "no page target" }
$wsUrl = [string]($target.webSocketDebuggerUrl)

$ws = New-Object System.Net.WebSockets.ClientWebSocket
$cts = New-Object System.Threading.CancellationTokenSource
$cts.CancelAfter([TimeSpan]::FromSeconds(60))
$ws.ConnectAsync([Uri]$wsUrl, $cts.Token).Wait(15000) | Out-Null

function Send-Cdp([int]$id, [string]$method, [hashtable]$params) {
    $payload = @{ id = $id; method = $method; params = $params } | ConvertTo-Json -Depth 20 -Compress
    $bytes = [Text.Encoding]::UTF8.GetBytes($payload)
    $seg = New-Object 'System.ArraySegment[byte]' -ArgumentList @(,$bytes)
    $ws.SendAsync($seg, [System.Net.WebSockets.WebSocketMessageType]::Text, $true, $cts.Token).Wait(15000) | Out-Null
}

function Receive-Cdp([int]$waitId) {
    while ($true) {
        $buf = New-Object byte[] 4194304
        $sb = New-Object Text.StringBuilder
        do {
            $seg = New-Object 'System.ArraySegment[byte]' -ArgumentList @(,$buf)
            $task = $ws.ReceiveAsync($seg, $cts.Token)
            if (-not $task.Wait(60000)) { throw "receive timeout" }
            $res = $task.Result
            [void]$sb.Append([Text.Encoding]::UTF8.GetString($buf, 0, $res.Count))
        } while (-not $res.EndOfMessage)
        $obj = $sb.ToString() | ConvertFrom-Json
        if ($obj.id -eq $waitId) { return $obj }
    }
}

Send-Cdp 1 'Page.enable' @{}
$p = @{ format = 'png'; fromSurface = $true }
if ($Width -gt 0) { $p.clip = @{ x = 0; y = 0; width = $Width; height = $Height; scale = 1 } }
Send-Cdp 2 'Page.captureScreenshot' $p
$resp = Receive-Cdp 2
$b64 = $resp.result.data
[IO.File]::WriteAllBytes($Out, [Convert]::FromBase64String($b64))
try { $ws.CloseAsync([System.Net.WebSockets.WebSocketCloseStatus]::NormalClosure, 'done', [Threading.CancellationToken]::None).Wait(3000) | Out-Null } catch { }
"saved $Out ($([IO.File]::ReadAllBytes($Out).Length) bytes)"
