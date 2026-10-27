# Assemble a Galaxy A51 boot image that boots the SWEETXNU payload.
#
#   powershell -ExecutionPolicy Bypass -File tools\a51\make-boot.ps1 `
#       -Kernel xnu\out-a51\kernel.development -Out out\boot-a51.img
#
# Layout of the result, and why:
#   boot.img kernel  = shim/a51/out/loader.bin (the diagnostic shim, a raw ARM64
#                      Image). S-Boot relocates the Image every boot, so the
#                      shim is built relocation-free and finds its own base.
#   boot.img ramdisk = the SWEETXNU payload (kernel segments + ADT + cmdline).
#                      S-Boot does NOT decompress the ramdisk: it copies the
#                      bytes as-is to 0x89000000 and advertises them through
#                      /chosen/linux,initrd-{start,end}, which is where the shim
#                      picks it up and validates the SWEETXNU magic. Boot 9
#                      proved this the hard way: with mkboot.js's default
#                      (--ramdisk-compress auto, copying the stock gzip magic)
#                      the shim saw the 6 170 624-byte gzip stream instead of
#                      the payload and requested recovery. So the ramdisk is
#                      written raw by default here; at 16 499 584 bytes it ends
#                      at ~0x89FBC400, under the FDT at 0x8A100000.
# The stock DTB and every trailing byte of the stock image are preserved.
param(
    [Parameter(Mandatory = $true)][string]$Kernel,
    [Parameter(Mandatory = $true)][string]$Out,
    [string]$Stock = 'backup\stock-boot.img',
    [string]$BootArgs = '',
    [string]$Canvas = '1080x2400',
    [ValidateSet('raw', 'gzip')][string]$RamdiskCompress = 'raw',
    [switch]$SkipShim
)
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path))
$py = 'G:\a51-port\toolchain\python\python.exe'
if (-not (Test-Path $py)) { throw "python missing: $py" }
# Node is not on PATH in this environment (installed outside Program Files).
$node = 'E:\node.js\node.exe'
if (-not (Test-Path $node)) {
    $cmd = Get-Command node -ErrorAction SilentlyContinue
    if (-not $cmd) { throw 'node not found (expected E:\node.js\node.exe)' }
    $node = $cmd.Source
}
$work = Join-Path $repo 'out\a51-payload'
New-Item -ItemType Directory -Force -Path $work | Out-Null
New-Item -ItemType Directory -Force -Path (Split-Path -Parent (Join-Path $repo $Out)) | Out-Null

if (-not $BootArgs) {
    # cpus=1: one Cortex-A53 (MPIDR 0) until the A51 topology is proven.
    # wdt=-1: S-Boot's watchdog must not fire while we decode a panic.
    # serial=3 keeps the pe_serial console path armed; on this device that
    # console is the ramoops PMSG zone -> /sys/fs/pstore/pmsg-ramoops-0.
    $BootArgs = 'debug=0xc serial=3 cpus=1 keepsyms=1 -enable_kprintf_spam ' +
                '-noprogress wdt=-1 wdt_test=no_user_checkin'
}

$kernelPath = (Resolve-Path $Kernel).Path
$stockPath = (Resolve-Path (Join-Path $repo $Stock)).Path
Write-Host "kernel : $kernelPath"
Write-Host "stock  : $stockPath"
Write-Host "args   : $BootArgs"

if (-not $SkipShim) {
    Write-Host ''
    Write-Host '== shim'
    & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $repo 'shim\a51\build.ps1')
    if ($LASTEXITCODE) { throw 'shim build failed' }
}
$loader = Join-Path $repo 'shim\a51\out\loader.bin'
if (-not (Test-Path $loader)) { throw "shim not built: $loader" }

Write-Host ''
Write-Host '== ADT'
$adt = Join-Path $work 'a51.adt'
& $py (Join-Path $repo 'tools\mkadt_a51.py') $adt --canvas $Canvas
if ($LASTEXITCODE) { throw 'mkadt_a51 failed' }

Write-Host ''
Write-Host '== payload'
$payload = Join-Path $work 'payload.bin'
& $py (Join-Path $repo 'tools\mkpayload.py') $kernelPath $adt $payload --cmdline $BootArgs
if ($LASTEXITCODE) { throw 'mkpayload failed' }

Write-Host ''
Write-Host '== boot image'
& $node (Join-Path $repo 'tools\a51\mkboot.js') --stock $stockPath `
    --kernel $loader --ramdisk $payload --ramdisk-compress $RamdiskCompress `
    --out (Join-Path $repo $Out)
if ($LASTEXITCODE) { throw 'mkboot failed' }

Write-Host ''
$img = Join-Path $repo $Out
$size = (Get-Item $img).Length
Write-Host "image size : $size bytes"
if ($RamdiskCompress -eq 'raw') {
    # S-Boot puts the ramdisk at 0x89000000; the FDT sits at 0x8a100000.
    # PowerShell parses 0x89000000/0x8a100000 as negative Int32, so keep the
    # whole comparison in Int64.
    [int64]$rdBase = 2298478592      # 0x89000000
    [int64]$fdtBase = 2316300288     # 0x8a100000
    [int64]$end = $rdBase + (Get-Item $payload).Length
    [int64]$headroom = $fdtBase - $end
    Write-Host ('ramdisk end: 0x{0:x} (FDT 0x8a100000, headroom {1} bytes)' -f $end, $headroom)
    if ($end -ge $fdtBase) { throw 'raw payload would overlap the FDT' }
}
Get-FileHash $img -Algorithm SHA256 | Format-List
