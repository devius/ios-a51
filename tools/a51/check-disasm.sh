#!/bin/bash
K=/mnt/g/a51-port/ios-a51/out/kernel.development.a5xelte
echo "== _start_first_cpu first 48 instructions =="
llvm-objdump -d --no-show-raw-insn --start-address=0xfffffff0074260dc --stop-address=0xfffffff007426200 "$K" 2>/dev/null | head -60

echo
echo "== literal pools near _start_first_cpu (raw bytes) =="
python3 - "$K" <<'PY'
import struct, sys
b = open(sys.argv[1],'rb').read()
# __TEXT_EXEC: vm 0xfffffff00725c000 fileoff 0x258000
base_vm, base_off = 0xfffffff00725c000, 0x258000
start = 0xfffffff0074260dc
off = base_off + (start - base_vm)
print('file offset of _start_first_cpu:', hex(off))
chunk = b[off:off+0x200]
for i in range(0, len(chunk), 4):
    w = struct.unpack_from('<I', chunk, i)[0]
    # ADRP / ADD immediate decode is complex; just show 32-bit words that look like addresses
    if 0xf0000000 <= w <= 0xffffffff or 0x80000000 <= w <= 0x90000000:
        print(f'  +{i:#x}: word {w:#010x}')
PY
