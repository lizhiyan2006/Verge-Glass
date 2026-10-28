# Minimal Chrome DevTools Protocol client for WebView2 (PowerShell 5.1 compatible)
# Usage: powershell -ExecutionPolicy Bypass -File cdp-eval.ps1 -Script "1+1"
param(
    [Parameter(Mandatory = $false)][string]$Script = "",
    [string]$ScriptFile = "",
    [int]$Port = 9333,
    [string]$TargetMatch = "",
    [switch]$Raw
)

if ($ScriptFile) {
    $Script = [System.IO.File]::ReadAllText($ScriptFile, [Text.Encoding]::UTF8)
}
if (-not $Script) { Write-Error "no -Script or -ScriptFile given"; exit 1 }

$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$base = "http://127.0.0.1:$Port"

function Get-Targets {
    $list = Invoke-RestMethod -Uri "$base/json/list" -TimeoutSec 10
    return @($list)
}

$targets = Get-Targets
$target = $null
if ($TargetMatch) {
    $target = $targets | Where-Object { $_.url -like "*$TargetMatch*" } | Select-Object -First 1
}
if (-not $target) {
    $target = $targets | Where-Object { $_.type -eq 'page' } | Select-Object -First 1
}
if (-not $target) {
    Write-Error "no page target found on port $Port"
    exit 2
}

$ws = New-Object System.Net.WebSockets.ClientWebSocket
$ws.Options.KeepAliveInterval = [TimeSpan]::FromSeconds(5)
$cts = New-Object System.Threading.CancellationTokenSource
$cts.CancelAfter([TimeSpan]::FromSeconds(30))
try {
    $ws.ConnectAsync([Uri]$target.webSocketDebuggerUrl, $cts.Token).Wait(15000) | Out-Null
} catch {
    Write-Error "connect failed: $($_.Exception.GetBaseException().Message)"
    exit 3
}
if ($ws.State -ne [System.Net.WebSockets.WebSocketState]::Open) {
    Write-Error "websocket state: $($ws.State)"
    exit 4
}

$script:msgId = 0
function Send-Cdp {
    param([string]$Method, [hashtable]$Params)
    $script:msgId++
    $payload = @{ id = $script:msgId; method = $Method; params = $Params } | ConvertTo-Json -Depth 20 -Compress
    $bytes = [Text.Encoding]::UTF8.GetBytes($payload)
    $seg = New-Object 'System.ArraySegment[byte]' -ArgumentList @(,$bytes)
    $ws.SendAsync($seg, [System.Net.WebSockets.WebSocketMessageType]::Text, $true, $cts.Token).Wait(15000) | Out-Null
    return $script:msgId
}

function Receive-Cdp {
    param([int]$WaitForId)
    while ($true) {
        $buf = New-Object byte[] 1048576
        $sb = New-Object Text.StringBuilder
        do {
            $seg = New-Object 'System.ArraySegment[byte]' -ArgumentList @(,$buf)
            $task = $ws.ReceiveAsync($seg, $cts.Token)
            if (-not $task.Wait(30000)) { throw "receive timeout" }
            $res = $task.Result
            [void]$sb.Append([Text.Encoding]::UTF8.GetString($buf, 0, $res.Count))
        } while (-not $res.EndOfMessage)
        $text = $sb.ToString()
        if ($Raw) { Write-Output $text }
        $obj = $text | ConvertFrom-Json
        if ($obj.id -eq $WaitForId) { return $obj }
    }
}

[void](Send-Cdp -Method 'Runtime.enable' -Params @{})
$id = Send-Cdp -Method 'Runtime.evaluate' -Params @{
    expression          = $Script
    returnByValue       = $true
    awaitPromise        = $true
    userGesture         = $true
    allowUnsafeEvalBlockedByCSP = $true
}
$resp = Receive-Cdp -WaitForId $id

try { $ws.CloseAsync([System.Net.WebSockets.WebSocketCloseStatus]::NormalClosure, 'done', [Threading.CancellationToken]::None).Wait(3000) | Out-Null } catch { }

if ($resp.error) {
    $resp | ConvertTo-Json -Depth 20
    exit 5
}
$r = $resp.result.result
if ($r.subtype -eq 'error' -or $resp.result.exceptionDetails) {
    $resp.result.exceptionDetails | ConvertTo-Json -Depth 20
    exit 6
}
if ($r.value -is [string]) {
    Write-Output $r.value
} elseif ($null -ne $r.value) {
    $r.value | ConvertTo-Json -Depth 20
} elseif ($r.description) {
    Write-Output $r.description
}
