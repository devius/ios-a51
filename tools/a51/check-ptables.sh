#!/bin/bash
T=/home/nickolay/xnuwork/xnu
echo "== start.s 690..815 (page table build + MMU enable) =="
sed -n '690,815p' "$T/osfmk/arm64/start.s" | nl -ba -v690
