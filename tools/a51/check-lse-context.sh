#!/bin/bash
K=/mnt/g/a51-port/ios-a51/out/kernel.development.a5xelte
echo "== which section is 0xfffffff007b19d14 in, and what is K256? =="
llvm-objdump --macho --section-headers "$K" | awk 'NR<4 || /__const|__text|__cstring|__TEXT_EXEC/'
echo
echo "== symbol K256 =="
llvm-nm -m --defined-only "$K" 2>/dev/null | grep -i ' K256$\| _K256\| K256' | head
echo
echo "== llvm-objdump around K256 with section context =="
llvm-objdump -d --no-show-raw-insn --disassemble-symbols=K256 "$K" 2>/dev/null | head -20
echo
echo "== does the const section live inside __TEXT_EXEC or __TEXT? =="
python3 - "$K" <<'PY'
import struct, sys
b = open(sys.argv[1],'rb').read()
ncmds, = struct.unpack_from('<I', b, 16)
off = 32
target = 0xfffffff007b19d14
for _ in range(ncmds):
    cmd, size = struct.unpack_from('<II', b, off)
    if cmd == 0x19:
        name = b[off+8:off+24].split(b'\0')[0].decode()
        vmaddr, vmsize, fileoff, filesize = struct.unpack_from('<4Q', b, off+24)
        nsects, = struct.unpack_from('<I', b, off+64)
        s = off + 72
        for _ in range(nsects):
            sect = b[s:s+16].split(b'\0')[0].decode()
            seg = b[s+16:s+32].split(b'\0')[0].decode()
            addr, sz, o = struct.unpack_from('<3Q', b, s+32)
            flags, = struct.unpack_from('<I', b, s+64)
            if addr <= target < addr + max(sz, 1):
                print(f'HIT: {seg},{sect} addr {addr:#x} size {sz:#x} fileoff {o:#x} '
                      f'flags {flags:#x} (VM_PROT/attr)')
                print(f'  contains {target:#x} at offset +{target-addr:#x}')
            if sect == '__const' or sect == '__text':
                pass
            s += 80
    off += size
PY
echo
echo "== whats actually at that offset (raw bytes) =="
python3 - "$K" <<'PY'
import struct, sys
b = open(sys.argv[1],'rb').read()
target = 0xfffffff007b19d14
# find the segment/section containing it, then map to file offset
ncmds, = struct.unpack_from('<I', b, 16)
off = 32
for _ in range(ncmds):
    cmd, size = struct.unpack_from('<II', b, off)
    if cmd == 0x19:
        vmaddr, vmsize, fileoff, filesize = struct.unpack_from('<4Q', b, off+24)
        nsects, = struct.unpack_from('<I', b, off+64)
        s = off + 72
        for _ in range(nsects):
            sect = b[s:s+16].split(b'\0')[0].decode()
            seg = b[s+16:s+32].split(b'\0')[0].decode()
            addr, sz, o = struct.unpack_from('<3Q', b, s+32)
            if addr <= target < addr + max(sz,1):
                fo = o + (target - addr)
                print(f'{seg},{sect}: file offset {fo:#x}')
                print('bytes:', b[fo-8:fo+16].hex(' '))
            s += 80
    off += size
PY
