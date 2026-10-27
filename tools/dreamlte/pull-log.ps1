param([string]$Name = (Get-Date -Format 'yyyyMMdd-HHmmss'))
# Pull the previous boot's console (pstore/ramoops) from TWRP and save the
# S8 probe report. The probe writes its report three times because the RAM
# loses a few bits across a forced reboot; compare the copies if a value
# looks odd.
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$dir = Join-Path $root 'logs'
New-Item -ItemType Directory -Force $dir | Out-Null
$raw = Join-Path $dir "pstore-$Name.txt"
adb pull /sys/fs/pstore/console-ramoops-0 $raw | Out-Null
$text = [IO.File]::ReadAllText($raw)
$i = $text.IndexOf('S8PROBE-LOG BEGIN')
if ($i -lt 0) { Write-Output "no S8PROBE log in pstore (saved raw: $raw)"; exit 1 }
$report = $text.Substring($i)
$out = Join-Path $dir "probe-$Name.txt"
[IO.File]::WriteAllText($out, $report)
Write-Output "saved $out"
Write-Output $report
