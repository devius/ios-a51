#!/bin/bash
B=$HOME/a51-build-40452629749.txt
# Build step = between the "bash build.sh" group and the error marker.
s=$(grep -n '\[group\]Run bash build.sh' "$B" | head -1 | cut -d: -f1)
e=$(grep -n '##\[error\]Process completed' "$B" | head -1 | cut -d: -f1)
sed -n "${s},${e}p" "$B" > "$HOME/buildstep.txt"
echo "buildstep: $(wc -l < "$HOME/buildstep.txt") lines, $(wc -c < "$HOME/buildstep.txt") bytes"
echo "step started $s, error at $e (log has $(wc -l < "$B"))"

echo
echo "=== capital Error (not warnings) ==="
grep -n 'Error' "$HOME/buildstep.txt" | grep -v 'warning:' | head -20

echo
echo "=== last 6 timestamps ==="
sed -n "${e}p" "$B"
grep -oE '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:.]+Z' /home/nickolay/a51-job-40452629749.log | tail -3

echo
echo "=== tool prefixes seen (first 40 distinct) ==="
grep -oE '^[A-Za-z][A-Za-z0-9_+-]*(\[[0-9]+\])?: ' "$HOME/buildstep.txt" | sort | uniq -c | sort -rn | head -20
