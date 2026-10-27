#!/bin/bash
K=$HOME/kern-40455401179
cd "$K" || exit 1
echo "== lse.txt =="
cat kernel.development.a5xelte.lse.txt
echo
echo "== SHA256SUMS =="
cat SHA256SUMS
echo
echo "== file =="
file kernel.development.a5xelte
echo
echo "== Mach-O header (segments/entry via python) =="
python3 - <<'PY'
import struct
b = open('kernel.development.a5xelte','rb').read()
magic, cputype, cpusub, ftype, ncmds, sizeofcmds, flags, _ = struct.unpack_from('<8I', b, 0)
print(f'magic {magic:#x} cputype {cputype:#x} sub {cpusub:#x} ftype {ftype} ncmds {ncmds} flags {flags:#x}')
off = 32
for _ in range(ncmds):
    cmd, size = struct.unpack_from('<II', b, off)
    if cmd == 0x19:
        name = b[off+8:off+24].split(b'\0')[0].decode()
        vmaddr, vmsize, fileoff, filesize = struct.unpack_from('<4Q', b, off+24)
        print(f'  SEG {name:12s} vm {vmaddr:#x} vmsize {vmsize:#x} off {fileoff:#x} size {filesize:#x}')
    elif cmd == 0x5:
        entry, = struct.unpack_from('<Q', b, off + 16 + 32*8)
        print(f'  LC_UNIXTHREAD pc {entry:#x}')
    elif cmd == 0x80000034:
        dataoff, datasize = struct.unpack_from('<II', b, off+8)
        print(f'  LC_DYLD_CHAINED_FIXUPS off {dataoff:#x} size {datasize:#x}')
    off += size
print('file size', len(b))
PY
echo
echo "== llvm-objdump / objdump availability =="
command -v llvm-objdump llvm-objdump-21 objdump aarch64-linux-gnu-objdump 2>/dev/null
echo
echo "== copy into the repo =="
mkdir -p /mnt/g/a51-port/ios-a51/out
cp kernel.development.a5xelte /mnt/g/a51-port/ios-a51/out/kernel.development.a5xelte
cp a51.adt /mnt/g/a51-port/ios-a51/out/a51.ci-adt
ls -l /mnt/g/a51-port/ios-a51/out/
