# Copy the working-tree plugin into %LOCALAPPDATA%\VergeGlass without touching
# autostart entries; the running daemon reloads the page when plugin.json changes.
param([string]$DataDir = "$env:LOCALAPPDATA\VergeGlass")

$repo = Split-Path $PSScriptRoot -Parent
if (-not (Test-Path (Join-Path $repo 'plugin.json'))) { throw "not a Verge Glass repo: $repo" }
if (-not (Test-Path (Join-Path $DataDir 'src'))) { throw "not installed: $DataDir (run Install.cmd first)" }

Copy-Item (Join-Path $repo 'plugin.json') (Join-Path $DataDir 'plugin.json') -Force
Copy-Item (Join-Path $repo 'src\verge-glass.css') (Join-Path $DataDir 'src\verge-glass.css') -Force
Copy-Item (Join-Path $repo 'src\verge-glass.js') (Join-Path $DataDir 'src\verge-glass.js') -Force

$v = (Get-Content (Join-Path $DataDir 'plugin.json') -Raw | ConvertFrom-Json).version
"synced v$v to $DataDir"
