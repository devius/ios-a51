#!/bin/bash
S=$HOME/buildstep.txt
echo "=== 8 'error:' lines ==="
grep -n '^error:' "$S"
echo
echo "=== crash / stack dump context ==="
for n in $(grep -n '^Thread: ' "$S" | cut -d: -f1 | head -3); do
  echo "----- around line $n -----"
  sed -n "$((n-25)),$((n+25))p" "$S"
done
