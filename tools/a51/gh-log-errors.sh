#!/bin/bash
# Every line in the build step that mentions an error but is not a -W warning.
L=$(ls -S /tmp/job-*.log 2>/dev/null | head -1)
sed -n '357,124276p' "$L" | sed -E 's/^[0-9T:.Z-]+ //' > /tmp/buildstep.txt

echo "--- lines with 'error' (not warnings/docs) ---"
grep -in 'error' /tmp/buildstep.txt |
  grep -viE 'warning:|Werror|not found in the function declaration|-W' |
  head -40

echo
echo "--- lines with stderr-ish markers ---"
grep -nE '^\s*(clang|ld|make|ninja|bash|python3?)[: ]' /tmp/buildstep.txt | head -30

echo
echo "--- commands that ran (first token of each line starting with a known tool) ---"
grep -nE '^(/usr/bin/)?(make|xcrun|clang|ld|dtrace)' /tmp/buildstep.txt | head -20

echo
echo "--- total lines with 'error' ---"
grep -ic 'error' /tmp/buildstep.txt
