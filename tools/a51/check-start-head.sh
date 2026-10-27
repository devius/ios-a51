#!/bin/bash
T=/home/nickolay/xnuwork/xnu
echo "== start.s 1..135 =="
sed -n '1,135p' "$T/osfmk/arm64/start.s" | nl -ba
echo
echo "== symbol at entry 0xfffffff007424488 =="
K=/mnt/g/a51-port/ios-a51/out/kernel.development.a5xelte
llvm-nm -n "$K" 2>/dev/null | awk '$1 ~ /^fffffff00742/' | head -20
echo "--- nearest <= entry:"
llvm-nm -n "$K" 2>/dev/null | awk '{ if (strtonum("0x"$1) <= strtonum("0xfffffff007424488")) { last=$0 } } END { print last }'
