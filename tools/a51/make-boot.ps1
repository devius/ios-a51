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
#                      S-Boot decompresses the ramdisk and advertises it through
#                      /chosen/linux,initrd-{start,end}, which is where the shim
#                      picks it up. Because the stock ramdisk is gzip, mkboot.js
#                      gzips ours too by default (--ramdisk-compress auto).
# The stock DTB and every trailing byte of the stock image are preserved.
param(
    [Parameter(Mandatory = $true)][string]$Kernel,
    [Parameter(Mandatory = $true)][string]$Out,
    [string]$Stock = 'backup\stock-boot.img',
    [string]$BootArgs = '',
    [string]$Canvas = '1080x2400',
    [switch]$SkipShim
)
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$py = 'G:\a51-port\toolchain\python\python.exe'
if (-not (Test-Path $py)) { throw "python missing: $py" }
$node = 'node'
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
    --kernel $loader --ramdisk $payload --out (Join-Path $repo $Out)
if ($LASTEXITCODE) { throw 'mkboot failed' }

Write-Host ''
Get-FileHash (Join-Path $repo $Out) -Algorithm SHA256 | Format-List
