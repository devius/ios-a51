#!/bin/bash
# Final check on the 0125 tree: the guards we wanted are extended, the ones we
# deliberately left alone are not, and no diff remains between the two routes.
set -uo pipefail
A=/home/nickolay/xnuwork124/xnu    # 0124 + apply-a51.py
B=/home/nickolay/xnuwork/xnu       # 0124 + 0125 patch

echo "== whole-tree diff (empty = the two routes agree) =="
diff -rq --exclude=.git "$A" "$B" && echo "  IDENTICAL TREES"

echo
echo "== guards extended for A51 (expect DREAMLTE || A51) =="
grep -rn 'defined(DREAMLTE) || defined(A51)' \
    "$B/osfmk/arm64/arm_vm_init.c" "$B/pexpert/arm/pe_serial.c" \
    "$B/iokit/Kernel/arm/SweetCPU.cpp" "$B/iokit/Kernel/arm/SweetFramebuffer.cpp" |
    sed "s#$B/##"

echo
echo "== guards deliberately left S8-only =="
grep -n 'defined(DREAMLTE)' "$B/iokit/Kernel/arm/SweetCPU.cpp" | sed 's/^/  SweetCPU /'
grep -n 'defined(DREAMLTE)' "$B/iokit/Kernel/arm/SweetFramebuffer.cpp" | sed 's/^/  SweetFB /'
grep -n 'defined(DREAMLTE)' "$B/bsd/dev/a5xelte_touch.c" | sed 's/^/  touch /'

echo
echo "== DECON base parameterised =="
grep -n 'A5_DECON_PHYS' "$B/iokit/Kernel/arm/SweetFramebuffer.cpp" \
    "$B/pexpert/pexpert/arm64/A5XELTE.h" | sed "s#$B/##"

echo
echo "== A51 board values =="
sed -n '/#if defined(A51)/,/#elif defined(DREAMLTE)/p' \
    "$B/pexpert/pexpert/arm64/A5XELTE.h" | grep -E '^#(define|undef)' | sed 's/^/  /'

echo
echo "== keys ALIVE base =="
sed -n '18,26p' "$B/bsd/dev/a5xelte_keys.c" | sed 's/^/  /'

echo
echo "== UFS node =="
grep -n 'UFS_ADT_NODE\|UFS_DEFAULT_PART' "$B/bsd/dev/sweet_ufs.c" | head -4 | sed 's/^/  /'
