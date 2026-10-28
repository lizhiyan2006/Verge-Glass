param([int]$Port = 9333)
$ErrorActionPreference = 'Stop'
$raw = (Invoke-WebRequest -Uri "http://127.0.0.1:$Port/json/list" -UseBasicParsing -TimeoutSec 10).Content
$docs = ConvertFrom-Json $raw
if ($docs -is [array] -and $docs.Count -eq 1 -and $docs[0] -is [array]) { $docs = $docs[0] }
$target = $null
foreach ($d in $docs) { if ($d.type -eq "page") { $target = $d; break } }
$ws = New-Object System.Net.WebSockets.ClientWebSocket
$cts = New-Object System.Threading.CancellationTokenSource
$ws.ConnectAsync([Uri]([string]$target.webSocketDebuggerUrl), $cts.Token).Wait(10000) | Out-Null
function Send-Cdp([int]$id, [string]$method, [hashtable]$params) {
    $payload = @{ id = $id; method = $method; params = $params } | ConvertTo-Json -Depth 20 -Compress
    $bytes = [Text.Encoding]::UTF8.GetBytes($payload)
    $seg = New-Object 'System.ArraySegment[byte]' -ArgumentList @(,$bytes)
    $ws.SendAsync($seg, [System.Net.WebSockets.WebSocketMessageType]::Text, $true, $cts.Token).Wait(10000) | Out-Null
}
function Receive-Cdp([int]$waitId) {
    while ($true) {
        $buf = New-Object byte[] 4194304
        $sb = New-Object Text.StringBuilder
        do {
            $seg = New-Object 'System.ArraySegment[byte]' -ArgumentList @(,$buf)
            $task = $ws.ReceiveAsync($seg, $cts.Token)
            $task.Wait(15000) | Out-Null
            $res = $task.Result
            [void]$sb.Append([Text.Encoding]::UTF8.GetString($buf, 0, $res.Count))
        } while (-not $res.EndOfMessage)
        $obj = $sb.ToString() | ConvertFrom-Json
        if ($obj.id -eq $waitId) { return $obj }
    }
}
Send-Cdp 1 'Emulation.setDefaultBackgroundColorOverride' @{ color = @{ r = 0; g = 0; b = 0; a = 0 } }
$r = Receive-Cdp 1
"override: " + ($r | ConvertTo-Json -Compress)
