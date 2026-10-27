#!/bin/bash
T=/home/nickolay/xnuwork/xnu
echo "== start.s 495..600 =="
sed -n '495,600p' "$T/osfmk/arm64/start.s" | nl -ba -v495
