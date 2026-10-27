param(
	[Parameter(Mandatory)][string]$Image,      # e.g. \\wsl.localhost\Ubuntu\root\s8\ios16-root.img
	[Parameter(Mandatory)][string]$Manifest,   # from chunk-manifest.py
	[string]$Partition = 'USERDATA',
	[string]$Progress = "$PSScriptRoot\..\..\..\research\flash-progress.txt"
)
# Write an image to a by-name partition of the phone in TWRP, in chunks:
# push a chunk to /tmp, dd it at its offset, then check the SHA-256 of what
# is now on the partition. All-zero chunks are written from /dev/zero on the
# phone. Verified chunk indexes go to $Progress, so a USB drop only costs a
# rerun. Writes nothing outside the named partition.
# 'Continue': adb writes progress to stderr, which Windows PowerShell turns
# into error records; failures are detected by exit code and checksum.
$ErrorActionPreference = 'Continue'
$m = Get-Content $Manifest -Raw | ConvertFrom-Json
$mib = [int]$m.chunk_mib
$size = $mib * 1MB
$dev = (adb shell "readlink -f /dev/block/platform/*/by-name/$Partition").Trim()
if ($dev -notmatch '^/dev/block/sd[a-z][0-9]+$') { throw "partition $Partition not found ($dev)" }
$psize = [int64](adb shell "blockdev --getsize64 $dev").Trim()
if ($psize -lt $m.chunks.Count * [int64]$size) { throw "$dev is $psize bytes, image does not fit" }
Write-Output "target $Partition = $dev ($psize bytes), $($m.chunks.Count) chunks of $mib MiB"
adb shell "umount /data 2>/dev/null; umount /sdcard 2>/dev/null; true" | Out-Null

$done = @{}
if (Test-Path $Progress) { Get-Content $Progress | ForEach-Object { $done[[int]$_] = $true } }
$fs = [IO.File]::OpenRead($Image)
$buf = New-Object byte[] $size
$tmp = Join-Path $env:TEMP 's8chunk.bin'
try {
	foreach ($c in $m.chunks) {
		$i = [int]$c.i
		if ($done[$i]) { continue }
		for ($try = 1; ; $try++) {
			try {
				if ($c.zero) {
					adb shell "dd if=/dev/zero of=$dev bs=1048576 seek=$($i * $mib) count=$mib conv=notrunc 2>/dev/null" | Out-Null
				} else {
					$fs.Position = [int64]$i * $size
					$n = 0
					while ($n -lt $size) { $r = $fs.Read($buf, $n, $size - $n); if ($r -le 0) { throw 'short read' }; $n += $r }
					[IO.File]::WriteAllBytes($tmp, $buf)
					adb push $tmp /tmp/c.bin *> $null
					if ($LASTEXITCODE -ne 0) { throw 'push failed' }
					adb shell "dd if=/tmp/c.bin of=$dev bs=1048576 seek=$($i * $mib) conv=notrunc 2>/dev/null; rm -f /tmp/c.bin" | Out-Null
				}
				$got = (adb shell "dd if=$dev bs=1048576 skip=$($i * $mib) count=$mib 2>/dev/null | sha256sum").Trim().Split(' ')[0]
				if ($got -ne $c.sha) { throw "verify mismatch ($got)" }
				Add-Content $Progress $i
				break
			} catch {
				Write-Output "chunk $i try $try failed: $_"
				if ($try -ge 8) { throw }
				for ($w = 0; $w -lt 30 -and -not (adb get-state 2>$null); $w++) { Start-Sleep 2 }
			}
		}
		if ($i % 16 -eq 0) { Write-Output ("chunk {0}/{1}" -f ($i + 1), $m.chunks.Count) }
	}
} finally {
	$fs.Close()
	Remove-Item $tmp -ErrorAction SilentlyContinue
}
adb shell "sync" | Out-Null
Write-Output "all $($m.chunks.Count) chunks written and verified on $dev"
