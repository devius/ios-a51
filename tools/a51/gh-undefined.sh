#!/bin/bash
B=$HOME/buildlog/build.log
echo "=== undefined symbols block ==="
n=$(grep -n 'Undefined symbols for architecture' "$B" | head -1 | cut -d: -f1)
sed -n "${n},$((n+60))p" "$B"
echo
echo "=== every 'referenced from' / symbol in the block ==="
sed -n "${n},$((n+400))p" "$B" | grep -E '^\s+"_|referenced from' | head -40
