# Pull the ramoops records that survive a boot, via /sys/fs/pstore.
#
# Run while the phone is back in a bootable state (recovery/Android): pstore is
# served by whatever kernel is running now, reading the reserved ramoops region
# that the previous kernel wrote. On this device the A51 shim reports into
# dmesg-ramoops-0 (with a forged "====" header so it is not zapped) and the XNU
# console ring goes to pmsg-ramoops-0.
#
#   powershell -ExecutionPolicy Bypass -File tools\a51\pull-pstore.ps1
#   powershell -ExecutionPolicy Bypass -File tools\a51\pull-pstore.ps1 -Show pmsg
#
param([string]$Show = 'all')
$ErrorActionPreference = 'Continue'
$adb  = 'E:\platform-tools-latest-windows\platform-tools\adb.exe'
$root = 'G:\a51-port\ios-a51'
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$out = Join-Path $root "backup\logs\pstore-$stamp"
New-Item -ItemType Directory -Force -Path $out | Out-Null

& $adb wait-for-device
$id = (& $adb shell 'id' 2>&1) -join ' '
$prefix = ''
if ($id -notmatch 'uid=0') {
    if (((& $adb shell 'su -c id' 2>&1) -join ' ') -match 'uid=0') { $prefix = 'su -c ' }
}
Write-Host "identity: $id (prefix '$prefix')"
Write-Host "saving to: $out"

$listing = (& $adb shell 'ls -l /sys/fs/pstore' 2>&1) -join "`n"
Write-Host $listing
if ($listing -match 'No such file') {
    Write-Host 'no pstore on this kernel - the record did not survive' -ForegroundColor Yellow
    exit 1
}

$files = @()
foreach ($line in ($listing -split "`n")) {
    if ($line -match '^\s*[-\w]{10}\s+\d+\s+\d+\s+(\d+)\s+\S+\s+\S+\s+(\S+)\s*$') {
        $files += @{ name = $Matches[2]; size = [int]$Matches[1] }
    }
}
if (-not $files) { $files = @(@{ name = 'dmesg-ramoops-0' }, @{ name = 'pmsg-ramoops-0' }) }

foreach ($f in $files) {
    $dst = Join-Path $out $f.name
    $cat = 'cat /sys/fs/pstore/' + $f.name
    $cmd = if ($prefix) { "$prefix `"$cat`"" } else { "`"$cat`"" }
    cmd /c "`"$adb`" exec-out $cmd > `"$dst`" 2>nul"
    $len = if (Test-Path $dst) { (Get-Item $dst).Length } else { 0 }
    Write-Host ("{0}: {1} bytes" -f $f.name, $len)
}

# Printable view: pstore records are plain text after the record header, but a
# torn ring can hold binary. Drop NULs and non-printable bytes other than \n\t.
function Show-Text([string]$path) {
    if (-not (Test-Path $path)) { return }
    $bytes = [System.IO.File]::ReadAllBytes($path)
    $sb = New-Object System.Text.StringBuilder
    foreach ($b in $bytes) {
        if ($b -eq 10 -or $b -eq 9 -or ($b -ge 32 -and $b -lt 127)) { [void]$sb.Append([char]$b) }
        elseif ($b -eq 0) { [void]$sb.Append('.') }
    }
    Write-Host ("`n===== {0} =====" -f (Split-Path -Leaf $path)) -ForegroundColor Cyan
    $text = $sb.ToString()
    if ($text.Length -gt 60000) { $text = $text.Substring($text.Length - 60000) }
    Write-Host $text
}

foreach ($f in $files) {
    $name = $f.name
    if ($Show -ne 'all' -and $name -notmatch $Show) { continue }
    Show-Text (Join-Path $out $name)
}
