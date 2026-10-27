#!/bin/bash
T=/home/nickolay/xnuwork/xnu
echo "== every use of A5_KLOG_PHYS =="
grep -rn 'A5_KLOG_PHYS' "$T" --include=*.c --include=*.h --include=*.s --include=*.cpp | sed "s#$T/##"
echo
echo "== context around each use =="
for f in $(grep -rln 'A5_KLOG_PHYS' "$T" --include=*.c --include=*.h --include=*.s --include=*.cpp); do
  echo "--- $f"
  grep -n -B6 -A14 'A5_KLOG_PHYS' "$f" | sed "s#$T/##"
done
