#!/bin/bash
T=/home/nickolay/xnuwork/xnu
echo "== start.s 135..265 =="
sed -n '135,265p' "$T/osfmk/arm64/start.s" | nl -ba -v135
