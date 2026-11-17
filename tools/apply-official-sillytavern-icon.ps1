$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$url = 'https://raw.githubusercontent.com/SillyTavern/SillyTavern/release/public/img/apple-icon-512x512.png'
$tmp = Join-Path $env:TEMP 'sillytavern-official-icon-512.png'
Write-Host 'Downloading the official SillyTavern 512x512 PWA icon...'
Invoke-WebRequest -Uri $url -OutFile $tmp -UseBasicParsing
Copy-Item $tmp (Join-Path $root 'AppScope/resources/base/media/app_icon.png') -Force
Copy-Item $tmp (Join-Path $root 'entry/src/main/resources/base/media/app_icon.png') -Force
Write-Host 'Official SillyTavern icon installed into AppScope and entry resources.' -ForegroundColor Green
