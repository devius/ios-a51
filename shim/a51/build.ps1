# Build the A51 boot-1 diagnostic shim on Windows with the xpack bare-metal GCC.
#   powershell -ExecutionPolicy Bypass -File shim\a51\build.ps1
$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$tool = 'G:\a51-port\toolchain\gcc\xpack-aarch64-none-elf-gcc-13.3.1-1.1\bin'
$cc = Join-Path $tool 'aarch64-none-elf-gcc.exe'
if (-not (Test-Path $cc)) { throw "toolchain missing: $cc" }
$env:PATH = $tool + ';' + $env:PATH

$cflags = @(
    '-O2', '-ffreestanding', '-nostdlib', '-fno-pic', '-fno-pie', '-fno-builtin',
    '-mgeneral-regs-only', '-mstrict-align', '-fno-stack-protector',
    '-fno-asynchronous-unwind-tables', '-march=armv8-a', '-Wall', '-Wextra', '-Werror'
)

$out = Join-Path $here 'out'
New-Item -ItemType Directory -Force -Path $out | Out-Null
Push-Location $here
try {
    & $cc @cflags '-c' 'start.S' '-o' 'out/start.o'
    if ($LASTEXITCODE) { throw 'start.S failed' }
    & $cc @cflags '-c' 'main.c' '-o' 'out/main.o'
    if ($LASTEXITCODE) { throw 'main.c failed' }
    & $cc @cflags '-c' 'ufs_probe.c' '-o' 'out/ufs_probe.o'
    if ($LASTEXITCODE) { throw 'ufs_probe.c failed' }

    $rel = & (Join-Path $tool 'aarch64-none-elf-readelf.exe') '-r' 'out/start.o' 'out/main.o' 'out/ufs_probe.o'
    $abs = ($rel | Select-String 'ABS64').Count
    if ($abs -ne 0) { throw "$abs absolute relocations; image would not be relocatable" }

    & $cc @cflags '-static' '-T' 'a51.ld' '-Wl,--build-id=none' '-Wl,--no-warn-rwx-segments' '-Wl,-N' 'out/start.o' 'out/main.o' 'out/ufs_probe.o' '-o' 'out/loader.elf'
    if ($LASTEXITCODE) { throw 'link failed' }
    & (Join-Path $tool 'aarch64-none-elf-objcopy.exe') '-O' 'binary' 'out/loader.elf' 'out/loader.bin'
    if ($LASTEXITCODE) { throw 'objcopy failed' }

    $endLine = & (Join-Path $tool 'aarch64-none-elf-nm.exe') 'out/loader.elf' | Select-String ' _end$'
    if ($endLine) {
        $end = [Convert]::ToInt64(($endLine.Line -split '\s+')[0], 16)
        $fs = [System.IO.File]::Open((Join-Path $here 'out/loader.bin'), 'Open', 'ReadWrite')
        if ($fs.Length -lt $end) { $fs.SetLength($end) }
        $fs.Close()
    }

    $bin = [System.IO.File]::ReadAllBytes((Join-Path $here 'out/loader.bin'))
    if ($bin.Length -lt 64) { throw 'loader.bin too small' }
    if (-not ($bin[56] -eq 0x41 -and $bin[57] -eq 0x52 -and $bin[58] -eq 0x4d -and $bin[59] -eq 0x64)) {
        throw 'bad ARM64 Image magic at offset 56'
    }
    # image_size (offset 16) must describe the copied payload, like stock.
    [System.BitConverter]::GetBytes([uint64]$bin.Length).CopyTo($bin, 16)
    [System.IO.File]::WriteAllBytes((Join-Path $here 'out/loader.bin'), $bin)
    "out/loader.bin: $($bin.Length) bytes; ARM64 Image header OK"
} finally {
    Pop-Location
}
