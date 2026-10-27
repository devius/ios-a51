# A51 Phase 1 capture, round 2: the first attempt reached the device but its adb
# shell was not root (/proc/cmdline, /sys/firmware/fdt and every dd came back
# "Permission denied"), and the phone dropped off the bus before we could retry.
#
# This version escalates before it reads anything: adb root -> su -c -> toybox
# busybox fallbacks, records which identity actually worked, and only then pulls
# the dumps. Read-only: it never writes a block device.
#
#   powershell -ExecutionPolicy Bypass -File tools\a51\phase1-dump2.ps1
#
$ErrorActionPreference = 'Continue'
$adb  = 'E:\platform-tools-latest-windows\platform-tools\adb.exe'
$root = 'G:\a51-port\ios-a51'
$bak  = Join-Path $root 'backup'
$out  = Join-Path $bak 'live'
New-Item -ItemType Directory -Force -Path $out | Out-Null
$log = Join-Path $bak 'phase1-dump.log'

function Log([string]$m) {
    $line = "{0} {1}" -f (Get-Date -Format 'HH:mm:ss'), $m
    Write-Host $line
    Add-Content -Path $log -Value $line
}

function Sh([string]$cmd) {
    # Returns stdout; stderr folded in so denials are visible.
    (& $adb shell $cmd 2>&1) -join "`n"
}

Log 'round 2: waiting for the device to come back...'
& $adb wait-for-device
Start-Sleep -Seconds 2
Log ("state: " + (& $adb get-state))

# --- identity / escalation ---------------------------------------------------
Log ("id before escalation: " + (Sh 'id'))
$rootOut = (& $adb root 2>&1) -join ' '
Log "adb root: $rootOut"
Start-Sleep -Seconds 2
& $adb wait-for-device 2>$null
Log ("id after adb root: " + (Sh 'id'))

$haveRoot = $false
$idNow = Sh 'id'
if ($idNow -match 'uid=0') {
    $haveRoot = $true
    $prefix = ''
    Log 'escalation: adbd is root, no wrapper needed'
} else {
    $suTest = (Sh 'su -c id' 2>&1) -join ' '
    Log "su -c id: $suTest"
    if ($suTest -match 'uid=0') {
        $haveRoot = $true
        $prefix = 'su -c '
        Log 'escalation: su available, wrapping every command'
    } else {
        Log 'escalation: NO ROOT - dumps will be attempted unprivileged and may fail'
        $prefix = ''
    }
}

# Which recovery/kernel is actually running? Tells us if this is TWRP or Android.
Log ("recovery: " + (Sh 'cat /tmp/recovery.log 2>/dev/null | head -1'))
Log ("uname: " + (Sh "$prefix uname -a"))
Log ("props: " + (Sh 'getprop ro.boot.dtbo_idx; getprop ro.boot.revision; getprop ro.bootloader; getprop ro.build.version.release; getprop ro.product.device'))

function Capture([string]$name, [string]$cmd) {
    $dst = Join-Path $out $name
    $wrapped = if ($prefix) { "$prefix `"$cmd`"" } else { $cmd }
    cmd /c "`"$adb`" exec-out $wrapped > `"$dst`" 2>nul"
    $len = if (Test-Path $dst) { (Get-Item $dst).Length } else { 0 }
    $head = ''
    if ($len -gt 0 -and $len -lt 4096) { $head = ((Get-Content $dst -Raw) -replace '\s+', ' ') }
    if ($len -eq 0) { Log ("$name : EMPTY") }
    elseif ($head -match 'denied|not found|No such') { Log ("$name : DENIED ($head)") }
    else { Log ("$name : $len bytes") }
}

Capture 'cmdline.txt'    'cat /proc/cmdline'
Capture 'iomem.txt'      'cat /proc/iomem'
Capture 'dmesg.txt'      'dmesg'
Capture 'fdt.dtb'        'cat /sys/firmware/fdt'
Capture 'mounts.txt'     'cat /proc/mounts'
Capture 'by-name.txt'    'ls -l /dev/block/by-name/'
Capture 'cpuinfo.txt'    'cat /proc/cpuinfo'
Capture 'pstore.txt'     'ls -l /sys/fs/pstore/ 2>&1'
Capture 'devmem-probe.txt' 'ls -l /dev/mem /dev/kmem 2>&1; head -c 64 /dev/mem | od -An -tx1 2>&1'

if ($haveRoot) {
    Log 'reading partitions (read-only)...'
    foreach ($p in @('boot', 'dtbo', 'vbmeta', 'vbmeta_samsung', 'efs', 'misc')) {
        $dst = Join-Path $bak ("stock-$p.img")
        cmd /c "`"$adb`" exec-out `"dd if=/dev/block/by-name/$p 2>/dev/null`" > `"$dst`""
        $len = if (Test-Path $dst) { (Get-Item $dst).Length } else { 0 }
        if ($len -eq 0) { Log ("stock-$p.img : FAILED") } else { Log ("stock-$p.img : $len bytes") }
    }
    # on-device copy so a bad flash can be undone without a host
    & $adb shell "$prefix dd if=/dev/block/by-name/boot of=/sdcard/stock-boot.img bs=4096" 2>$null
    Log ("on-device copy: " + (Sh "$prefix ls -l /sdcard/stock-boot.img"))
} else {
    Log 'skipping partition images: no root'
}

Log 'round 2 done'
