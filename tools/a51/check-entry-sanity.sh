#!/bin/bash
K=/mnt/g/a51-port/ios-a51/out/kernel.development.a5xelte
T=/home/nickolay/xnuwork/xnu

echo "== __start (entry) instructions =="
llvm-objdump -d --no-show-raw-insn --start-address=0xfffffff007424488 --stop-address=0xfffffff0074244a0 "$K" 2>/dev/null | tail -6

echo
echo "== La5_draw_text: what stores does it use? =="
s=$(grep -n 'La5_draw_text:' "$T/osfmk/arm64/start.s" | cut -d: -f1)
echo "starts at line $s"
sed -n "${s},$((s+40))p" "$T/osfmk/arm64/start.s" | grep -n 'str\|stur\|stp\|MOV64\|and\|lsl' | head -20

echo
echo "== every 8-byte (x-register) store in the A5XELTE-guarded early blocks =="
awk 'NR>=515 && NR<=545 || NR>=890 && NR<=1045' "$T/osfmk/arm64/start.s" | grep -n 'str[[:space:]]*x' || echo "  none (all stores are 32-bit w-register or none)"
