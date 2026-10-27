# Build the A51 boot-1 shim and pack it into backup\boot-a51-test1.img.
# Prefers the stock boot image; falls back to the OrangeFox image (same
# header v2 / page 2048 / raw kernel layout) only while no stock dump exists.
#
#   powershell -ExecutionPolicy Bypass -File tools\a51\build-all.ps1
$ErrorActionPreference = 'Stop'
$root = 'G:\a51-port\ios-a51'
$bak  = Join-Path $root 'backup'
$stock = Join-Path $bak 'stock-boot.img'
$orh   = 'G:\a51-port\OrangeFox-Unofficial-a51.img'
$out   = Join-Path $bak 'boot-a51-test1.img'
New-Item -ItemType Directory -Force -Path $bak | Out-Null

& powershell -ExecutionPolicy Bypass -File (Join-Path $root 'shim\a51\build.ps1')

if (Test-Path $stock) { $base = $stock; $force = @() }
elseif (Test-Path $orh) { $base = $orh; $force = @('--force', 'raw') }
else { throw 'no stock-boot.img and no OrangeFox image to use as a template' }

Write-Host "template: $base"
& 'E:\node.js\node.exe' (Join-Path $root 'tools\a51\mkboot.js') `
    --stock $base --kernel (Join-Path $root 'shim\a51\out\loader.bin') --out $out @force

Get-Item $out | Select-Object FullName, Length, LastWriteTime | Format-List
