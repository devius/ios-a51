# Pull the A51 shim log records out of the surviving Samsung log regions.
# Run while the phone is in TWRP (its adb still works while our shim reboots).
#
#   powershell -ExecutionPolicy Bypass -File tools\a51\pull-log.ps1
#
$ErrorActionPreference = 'Continue'
$adb  = 'E:\platform-tools-latest-windows\platform-tools\adb.exe'
$root = 'G:\a51-port\ios-a51'
$bak  = Join-Path $root 'backup'
$out  = Join-Path $bak 'logs'
New-Item -ItemType Directory -Force -Path $out | Out-Null

# physical / 4096 for each surviving region
$regions = @(
    @{ name = 'sec_avc_log';   skip = 594434; label = '0x91202000' },
    @{ name = 'sec_disp_log';  skip = 594566; label = '0x91286000' },
    @{ name = 'sec_debug_next'; skip = 594824; label = '0x91388000' },
    @{ name = 'ess_setup';     skip = 1019904; label = '0xF9000000' }
)

& $adb wait-for-device

# /dev/mem needs root in most recoveries. adbd here is already root, and
# `adb root` would only restart it and hang wait-for-device.
$id = (& $adb shell 'id' 2>&1) -join ' '
$prefix = ''
if ($id -notmatch 'uid=0') {
    if (((& $adb shell 'su -c id' 2>&1) -join ' ') -match 'uid=0') { $prefix = 'su -c ' }
}
Write-Host "identity: $id (prefix '$prefix')"

foreach ($r in $regions) {
    $dst = Join-Path $out ($r.name + '.bin')
    $dd = "dd if=/dev/mem bs=4096 skip=$($r.skip) count=1 2>/dev/null"
    $cmd = if ($prefix) { "$prefix `"$dd`"" } else { "`"$dd`"" }
    cmd /c "`"$adb`" exec-out $cmd > `"$dst`""
    $len = if (Test-Path $dst) { (Get-Item $dst).Length } else { 0 }
    if ($len -ge 24) {
        Write-Host ("{0} ({1}): {2} bytes" -f $r.name, $r.label, $len)
    } else {
        Write-Host ("{0} ({1}): NO DATA (len={2}) - /dev/mem may be restricted" -f $r.name, $r.label, $len)
        Remove-Item $dst -ErrorAction SilentlyContinue
    }
}

$decoder = Join-Path $root 'tools\a51\decode-log.js'
if (Test-Path $decoder) {
    & 'E:\node.js\node.exe' $decoder $out
}

# Fallback: TWRP kernels often block /dev/mem but expose /proc/kcore, whose
# ELF program headers let us seek straight to a physical address.
$missing = $regions | Where-Object { -not (Test-Path (Join-Path $out ($_.name + '.bin'))) }
if ($missing) {
    Write-Host "`n/dev/mem gave no data; trying /proc/kcore..."
    & 'E:\node.js\node.exe' (Join-Path $root 'tools\a51\kcore-log.js') $out $adb
}
