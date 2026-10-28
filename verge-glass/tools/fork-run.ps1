# Launch the Verge Glass fork build (native transparent window) with a CDP port.
# Requires the window to be created by the patched src-tauri (transparent + alpha 0).
param(
    [string]$Repo = 'C:\Users\394\Desktop\clash-glass\clash-verge-rev-dev',
    [ValidateSet('debug', 'release')][string]$Profile = 'debug',
    [int]$Port = 9333,
    [switch]$NoStop,
    [switch]$Wait
)

$ErrorActionPreference = 'Stop'

$candidates = @(
    (Join-Path $Repo "target\$Profile\clash-verge.exe"),
    (Join-Path $Repo "src-tauri\target\$Profile\clash-verge.exe")
)
$exe = $candidates | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $exe) { throw "build not found under: $($candidates -join ', ')" }

# Tauri keeps sidecars/resources next to the binary; mirror them if the build skipped that.
$sidecarDir = Join-Path $Repo 'src-tauri\sidecar'
$resDir = Join-Path $Repo 'src-tauri\resources'
$targetDir = Split-Path $exe -Parent
foreach ($f in Get-ChildItem $sidecarDir -Filter '*.exe' -ErrorAction SilentlyContinue) {
    $dest = Join-Path $targetDir $f.Name
    if (-not (Test-Path $dest) -or (Get-Item $dest).Length -ne $f.Length) { Copy-Item $f.FullName $dest -Force }
}
if (Test-Path $resDir) {
    $destRes = Join-Path $targetDir 'resources'
    if (-not (Test-Path $destRes)) { New-Item -ItemType Directory -Path $destRes | Out-Null }
    foreach ($f in Get-ChildItem $resDir -File) {
        $dest = Join-Path $destRes $f.Name
        if (-not (Test-Path $dest) -or (Get-Item $dest).Length -ne $f.Length) { Copy-Item $f.FullName $dest -Force }
    }
}

if (-not $NoStop) {
    # single-instance check keys off the app id, so the stock build must go first
    Get-Process clash-verge -ErrorAction SilentlyContinue | ForEach-Object {
        "stopping clash-verge pid $($_.Id)"; $_.CloseMainWindow() | Out-Null
    }
    Start-Sleep -Seconds 2
    Get-Process clash-verge -ErrorAction SilentlyContinue | ForEach-Object { "killing pid $($_.Id)"; $_ | Stop-Process -Force }
    Start-Sleep -Milliseconds 800
}

$env:WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS = "--remote-debugging-port=$Port"
$proc = Start-Process -FilePath $exe -PassThru
"started $Profile build pid $($proc.Id)"

if ($Wait) {
    $deadline = (Get-Date).AddSeconds(40)
    while ((Get-Date) -lt $deadline) {
        try {
            $r = Invoke-WebRequest "http://127.0.0.1:$Port/json/list" -TimeoutSec 2 -UseBasicParsing
            if ($r.StatusCode -eq 200) { "CDP ready on $Port"; ($r.Content | ConvertFrom-Json) | Select-Object type, url | Format-Table -AutoSize; break }
        } catch { }
        Start-Sleep -Milliseconds 500
    }
}
