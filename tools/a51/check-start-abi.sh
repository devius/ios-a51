#!/bin/bash
T=/home/nickolay/xnuwork/xnu
echo "== osfmk/arm64 start files =="
ls -l "$T/osfmk/arm64/" | grep -i 'start\|boot' 
echo
echo "== where is _start / boot_args ABI =="
grep -rn 'boot_args\|x0' "$T/osfmk/arm64/start.s" 2>/dev/null | head -40
echo
echo "== machine_boot / PE boot_args entry =="
grep -rn 'boot_args' "$T/osfmk/arm64/start.c" 2>/dev/null | head -20
