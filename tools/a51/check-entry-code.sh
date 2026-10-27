#!/bin/bash
K=/mnt/g/a51-port/ios-a51/out/kernel.development.a5xelte
T=/home/nickolay/xnuwork/xnu

echo "== is the marker constant in the built kernel? =="
python3 - "$K" <<'PY'
import sys
b = open(sys.argv[1], 'rb').read()
for name, pat in [('XNUELTE1', bytes.fromhex('584e5545544c4531')),
                  ('marker phys 0xf9e9000c', bytes.fromhex('0c00e9f9')),
                  ('fb phys 0xca000000', bytes.fromhex('000000ca')),
                  ('fb phys 0x12860000 (S8 DECON)', bytes.fromhex('00008612'))]:
    idx = b.find(pat)
    print(f'  {name:30s} {"FOUND at file off " + hex(idx) if idx >= 0 else "absent"} (count {b.count(pat)})')
PY

echo
echo "== board_config.h: how is A5XELTE / A51 defined? =="
grep -n 'A5XELTE\|define A51\|DREAMLTE\|SWEET' "$T/pexpert/pexpert/arm64/board_config.h" | head -30

echo
echo "== first instructions of start_first_cpu =="
llvm-objdump -d --no-show-raw-insn --disassemble-symbols=start_first_cpu "$K" 2>/dev/null | head -30

echo
echo "== start_first_cpu symbol address =="
llvm-nm "$K" 2>/dev/null | grep -E ' (start_first_cpu|__start)$'
