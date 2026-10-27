#!/bin/bash
T=/home/nickolay/xnuwork/xnu
K=/mnt/g/a51-port/ios-a51/out/kernel.development.a5xelte

echo "== who defines the bare A5XELTE / SWEET / DREAMLTE macros? =="
grep -rn '#define[[:space:]]*A5XELTE\b\|#define[[:space:]]*SWEET\b\|#define[[:space:]]*DREAMLTE\b' "$T" --include=*.h --include=*.c --include=*.S --include=*.s --include=*.xcconfig 2>/dev/null | sed "s#$T/##" | head -20

echo
echo "== build flags in the workflow / dxb =="
grep -rn 'A5XELTE' /mnt/g/a51-port/ios-a51/.github/workflows/xnu.yml | head -20

echo
echo "== symbols containing first_cpu =="
llvm-nm "$K" 2>/dev/null | grep -i 'first_cpu' | head
echo "-- any start_first:"
llvm-nm "$K" 2>/dev/null | grep -i 'start_first' | head
echo "-- nm symbol count:"
llvm-nm "$K" 2>/dev/null | wc -l

echo
echo "== does the kernel contain the green-block constant 0xff00ff00? =="
python3 - "$K" <<'PY'
import sys
b = open(sys.argv[1],'rb').read()
for name, pat in [('0xff00ff00', bytes.fromhex('00ff00ff')),
                  ('fb+88*4320+240*4 = 0xca05d3c0', bytes.fromhex('c0d305ca'))]:
    print(f'  {name:32s} count={b.count(pat)} first={hex(b.find(pat))}')
PY
