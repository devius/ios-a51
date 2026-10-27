# Flash a boot image to the BOOT partition only, with readback verification.
#
#   powershell -ExecutionPolicy Bypass -File tools\a51\flash-boot.ps1 -Image out\boot-a51.img
#   powershell -ExecutionPolicy Bypass -File tools\a51\flash-boot.ps1 -Restore
#   ... -NoReboot     flash and verify, then stop (phone stays in recovery)
#
# Hard rules from the project brief: boot (sda12) is the only partition this
# script may write. It never touches bootloader/sboot, efs, sec_efs, cpefs,
# modem/radio, persist, param, up_param or recovery, and it refuses to run
# unless the device name resolves to "boot" before the write.
param(
    [string]$Image = '',
    [switch]$Restore,
    [switch]$NoReboot
)
$ErrorActionPreference = 'Stop'
$adb  = 'E:\platform-tools-latest-windows\platform-tools\adb.exe'
$root = 'G:\a51-port\ios-a51'
$bak  = Join-Path $root 'backup'
$stock = Join-Path $bak 'stock-boot.img'

function Die([string]$m) { Write-Host "ABORT: $m" -ForegroundColor Red; exit 1 }

& $adb wait-for-device
$id = (& $adb shell 'id' 2>&1) -join ' '
$prefix = ''
if ($id -notmatch 'uid=0') {
    if (((& $adb shell 'su -c id' 2>&1) -join ' ') -match 'uid=0') { $prefix = 'su -c ' }
    else { Die "no root in this adb shell (id: $id)" }
}
Write-Host "identity: $id (prefix '$prefix')"

# Resolve the partition and refuse anything that is not literally "boot".
$link = (& $adb shell "readlink -f /dev/block/by-name/boot" 2>&1) -join ''
Write-Host "boot -> $link"
if ($link -notmatch 'by-name/boot$') { Die "by-name/boot did not resolve to itself ($link)" }

if ($Restore) {
    if (-not (Test-Path $stock)) { Die "no backup/stock-boot.img" }
    $Image = $stock
}
if (-not $Image) { Die "-Image is required (or -Restore)" }
$src = if (Test-Path $Image) { (Resolve-Path $Image).Path } else { Die "image not found: $Image" }
if ((Get-Item $src).Length -lt 1MB) { Die "$src looks truncated" }

$localHash = (Get-FileHash $src -Algorithm SHA256).Hash.ToLower()
Write-Host "image : $src"
Write-Host "sha256: $localHash"

$devTmp = '/tmp/' + (Split-Path -Leaf $src)
& $adb push $src $devTmp
$devHash = ((& $adb shell "$prefix sha256sum $devTmp") -join ' ') -split '\s+' | Select-Object -First 1
if ($devHash -ne $localHash) { Die "push hash mismatch: device=$devHash" }
Write-Host 'push verified'

& $adb shell "$prefix `"dd if=$devTmp of=/dev/block/by-name/boot bs=4096`""
& $adb shell "$prefix sync"

# Compare the first 64 KiB read back from the partition with the image, so a
# silent short write is caught before rebooting into a half-flashed boot.
$head = Join-Path $bak 'boot-readback-head.bin'
$ddRead = if ($prefix) { "$prefix `"dd if=/dev/block/by-name/boot bs=4096 count=16`"" } else { "dd if=/dev/block/by-name/boot bs=4096 count=16 2>/dev/null" }
cmd /c "`"$adb`" exec-out $ddRead > `"$head`""
$want = [System.IO.File]::ReadAllBytes($src)
$n = [Math]::Min(65536, $want.Length)
$got = [System.IO.File]::ReadAllBytes($head)
if ($got.Length -lt $n) { Die "readback truncated ($($got.Length) < $n)" }
for ($i = 0; $i -lt $n; $i++) { if ($got[$i] -ne $want[$i]) { Die "readback differs at byte $i" } }
Write-Host 'flash verified by readback'

if ($NoReboot) { Write-Host 'not rebooting (-NoReboot)'; exit 0 }

& $adb shell "$prefix reboot"
Write-Host 'rebooting; waiting for the device to come back'
$deadline = (Get-Date).AddMinutes(5)
while ((Get-Date) -lt $deadline) {
    Start-Sleep -Seconds 5
    $d = (& $adb devices) 2>$null | Select-String -Pattern '\bdevice$|\brecovery$'
    if ($d) { Write-Host 'device is back'; exit 0 }
}
Write-Host 'device did not return to adb; hold Vol+ + Power for recovery and run tools\a51\pull-pstore.ps1' -ForegroundColor Yellow
