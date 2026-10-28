# ============================================================
#  Verge Glass 一键安装器
#  用法：把整个文件夹复制到任意位置，双击 Install.cmd，
#        或在本目录执行：
#            powershell -ExecutionPolicy Bypass -File .\Install.ps1
#  可选参数：
#         -NoAutostart          不注册登录自启
#         -KeepAppAutoLaunch    保留 Clash Verge 自带的开机自启
#         -WriteCssInjection    同时把主题写进 App 的 CSS 注入（不启动插件也生效）
#         -UpdateUrl <url>      插件更新源（plugin.json 地址）
# ============================================================
[CmdletBinding()]
param(
    [switch]$NoAutostart,
    [switch]$KeepAppAutoLaunch,
    [switch]$WriteCssInjection,
    [string]$UpdateUrl = ""
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSCommandPath
$engine = Join-Path $root "VergeGlass.ps1"

if (-not (Test-Path $engine)) {
    Write-Host ""
    Write-Host "  [x] 找不到 VergeGlass.ps1，请确认 Install.ps1 与它在同一个文件夹。" -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "  Verge Glass installer" -ForegroundColor Cyan
Write-Host "  source : $root"
Write-Host ""

$argv = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $engine, "install")
if ($NoAutostart) { $argv += "-NoAutostart" }
if ($KeepAppAutoLaunch) { $argv += "-KeepAppAutoLaunch" }
if ($WriteCssInjection) { $argv += "-WriteCssInjection" }
if ($UpdateUrl) { $argv += @("-UpdateUrl", $UpdateUrl) }

& powershell @argv
if ($LASTEXITCODE -ne 0) {
    Write-Host ""
    Write-Host "  [x] 安装失败（exit $LASTEXITCODE）" -ForegroundColor Red
    exit $LASTEXITCODE
}

Write-Host ""
Write-Host "  [ok] 安装完成" -ForegroundColor Green
Write-Host "       - 设置卡片：Clash Verge -> 设置 -> 页面底部「半透明主题」"
Write-Host "       - 下次请从开始菜单「Clash Verge (Verge Glass)」启动，或重启电脑"
Write-Host "       - 卸载：运行 Uninstall.cmd"
Write-Host ""
