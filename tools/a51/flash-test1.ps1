# Flash boot-a51-test1.img to BOOT and collect the boot-1 evidence.
#
# Refuses to run without a local stock-boot.img, because that is the only
# guaranteed way back from a bad image. Writes only /dev/block/by-name/boot.
#
#   powershell -ExecutionPolicy Bypass -File tools\a51\flash-test1.ps1
#   powershell -ExecutionPolicy Bypass -File tools\a51\flash-test1.ps1 -Restore
#
param([switch]$Restore)

$ErrorActionPreference = 'Stop'
$adb  = 'E:\platform-tools-latest-windows\platform-tools\adb.exe'
$root = 'G:\a51-port\ios-a51'
$bak  = Join-Path $root 'backup'
$stock = Join-Path $bak 'stock-boot.img'
$test  = Join-Path $bak 'boot-a51-test1.img'

function Die([string]$m) { Write-Host "ABORT: $m" -ForegroundColor Red; exit 1 }

& $adb wait-for-device
$state = (& $adb get-state) 2>$null
Write-Host "adb device: $state"

# OrangeFox already runs adbd as root; `adb root` here just restarts adbd and
# hangs wait-for-device, so only check the identity we already have.
$id = (& $adb shell 'id' 2>&1) -join ' '
$prefix = ''
if ($id -notmatch 'uid=0') {
    $suTest = (& $adb shell 'su -c id' 2>&1) -join ' '
    if ($suTest -match 'uid=0') { $prefix = 'su -c ' }
    else { Die "no root in this adb shell (id: $id) - cannot touch /dev/block" }
}
Write-Host "shell identity: $id (prefix '$prefix')"

if ($Restore) {
    if (-not (Test-Path $stock)) { Die "no backup/stock-boot.img to restore from" }
    & $adb push $stock /tmp/stock-boot.img
    & $adb shell "$prefix `"dd if=/tmp/stock-boot.img of=/dev/block/by-name/boot bs=4096`""
    & $adb shell "$prefix sync"
    & $adb shell "$prefix reboot"
    Write-Host 'stock boot restored'
    exit 0
}

if (-not (Test-Path $stock)) { Die "missing backup/stock-boot.img - run tools\a51\phase1-dump.ps1 first" }
if (-not (Test-Path $test))  { Die "missing backup/boot-a51-test1.img - build it first" }
if ((Get-Item $stock).Length -lt 8MB) { Die "stock-boot.img looks truncated" }

$localHash = (Get-FileHash $test -Algorithm SHA256).Hash.ToLower()
Write-Host "local image sha256: $localHash"

& $adb push $test /tmp/boot-a51-test1.img
$devHash = ((& $adb shell "$prefix sha256sum /tmp/boot-a51-test1.img") -join ' ') -split '\s+' | Select-Object -First 1
if ($devHash -ne $localHash) { Die "push hash mismatch: device=$devHash" }
Write-Host 'push verified'

& $adb shell "$prefix `"dd if=/tmp/boot-a51-test1.img of=/dev/block/by-name/boot bs=4096`""
& $adb shell "$prefix sync"

# Read back the first 8 pages and compare, so a silent write failure is caught
# before rebooting into a partial image.
$head = Join-Path $bak 'boot-readback-head.bin'
$ddCmd = if ($prefix) { "$prefix `"dd if=/dev/block/by-name/boot bs=4096 count=8`"" } else { "dd if=/dev/block/by-name/boot bs=4096 count=8 2>/dev/null" }
cmd /c "`"$adb`" exec-out $ddCmd > `"$head`""
$want = [System.IO.File]::ReadAllBytes($test)[0..32767]
$got  = [System.IO.File]::ReadAllBytes($head)
if ($got.Length -lt $want.Length) { Die "readback truncated" }
for ($i = 0; $i -lt $want.Length; $i++) { if ($got[$i] -ne $want[$i]) { Die "readback differs at byte $i" } }
Write-Host 'flash verified by readback'

& $adb shell "$prefix reboot"
Write-Host 'rebooting; waiting for the device to come back (shim runs 15 s, then resets)'

$deadline = (Get-Date).AddMinutes(4)
while ((Get-Date) -lt $deadline) {
    Start-Sleep -Seconds 5
    $d = (& $adb devices) 2>$null | Select-String -Pattern '\bdevice$|\brecovery$'
    if ($d) { break }
}
if ((Get-Date) -ge $deadline) { Die "device did not return to adb; use Vol+ + Power to enter recovery, then re-run phase1-dump" }

Start-Sleep -Seconds 3
& powershell -ExecutionPolicy Bypass -File (Join-Path $root 'tools\a51\pull-log.ps1')
