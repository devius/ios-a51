# A51 Phase 1 live capture (run while the phone sits in TWRP)
#
# Pulls the runtime facts the port needs: cmdline (framebuffer address,
# dtbo index, revision), iomem map, partition table, dmesg, live FDT, and
# stock images for every partition we are allowed to read. Read-only: it
# never writes to a block device. Safe to re-run.
#
#   powershell -ExecutionPolicy Bypass -File tools\a51\phase1-dump.ps1
#
$ErrorActionPreference = 'Continue'
$adb  = 'E:\platform-tools-latest-windows\platform-tools\adb.exe'
$root = 'G:\a51-port\ios-a51'
$bak  = Join-Path $root 'backup'
New-Item -ItemType Directory -Force -Path $bak | Out-Null

function Write-Log([string]$msg) {
    $line = "{0} {1}" -f (Get-Date -Format 'HH:mm:ss'), $msg
    Write-Host $line
    Add-Content -Path (Join-Path $bak 'phase1-dump.log') -Value $line
}

function Dump-Sh([string]$name, [string]$cmd) {
    $dst = Join-Path $bak $name
    cmd /c "`"$adb`" exec-out `"$cmd`" > `"$dst`" 2>nul"
    if (Test-Path $dst) {
        Write-Log ("{0}: {1} bytes" -f $name, (Get-Item $dst).Length)
    } else {
        Write-Log ("{0}: FAILED" -f $name)
    }
}

function Dump-Part([string]$name, [string]$part) {
    $dst = Join-Path $bak $name
    cmd /c "`"$adb`" exec-out `"dd if=/dev/block/by-name/$part 2>/dev/null`" > `"$dst`""
    if ((Test-Path $dst) -and (Get-Item $dst).Length -gt 0) {
        Write-Log ("{0}: {1} bytes" -f $name, (Get-Item $dst).Length)
    } else {
        Write-Log ("{0}: FAILED" -f $name)
    }
}

Write-Log 'waiting for a TWRP adb device...'
& $adb wait-for-device
$state = (& $adb get-state) 2>$null
Write-Log "device state: $state"

Dump-Sh 'cmdline.txt'      'cat /proc/cmdline'
Dump-Sh 'iomem.txt'        'cat /proc/iomem'
Dump-Sh 'partitions.txt'   'ls -l /dev/block/by-name/'
Dump-Sh 'twrp-dmesg.txt'   'dmesg'
Dump-Sh 'a51-live.dtb'     'cat /sys/firmware/fdt'
Dump-Sh 'mounts.txt'       'cat /proc/mounts'
Dump-Sh 'version.txt'      'getprop ro.boot.bootloader; getprop ro.boot.dtbo_idx; getprop ro.boot.revision; getprop ro.product.device'

Dump-Part 'stock-boot.img'   'boot'
Dump-Part 'stock-dtbo.img'   'dtbo'
Dump-Part 'stock-vbmeta.img' 'vbmeta'
Dump-Part 'stock-efs.img'    'efs'

# On-device copy of the kernel slot, so a bad flash can be undone from TWRP
# without a host connection.
& $adb shell "dd if=/dev/block/by-name/boot of=/sdcard/stock-boot.img bs=4096" 2>$null

Write-Log 'done'
