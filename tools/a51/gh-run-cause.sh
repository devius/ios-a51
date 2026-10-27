#!/bin/bash
B=$HOME/a51-build-40452629749.txt
echo "=== lines containing *** ==="
grep -n '\*\*\*' "$B" | head -20
echo
echo "=== exit/stop/failed ==="
grep -niE 'stop\.|exited with|exit code|failed|fatal' "$B" | grep -v 'warning' | head -20
echo
echo "=== kernel build region: 10380..10420 ==="
sed -n '10380,10420p' "$B"
echo
echo "=== last 60 lines before the ##[error] ==="
n=$(grep -n '##\[error\]' "$B" | head -1 | cut -d: -f1)
sed -n "$((n-60)),$((n))p" "$B"
