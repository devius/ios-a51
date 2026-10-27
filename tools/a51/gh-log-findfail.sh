#!/bin/bash
# Find the actual make failure in the build step (lines 357..124276).
L=$(ls -S /tmp/job-*.log 2>/dev/null | head -1)
sed -n '357,124276p' "$L" | sed -E 's/^[0-9T:.Z-]+ //' > /tmp/buildstep.txt
echo "build step lines: $(wc -l < /tmp/buildstep.txt)"

echo "--- make Error lines ---"
grep -nE 'make(\[[0-9]+\])?: \*\*\*|Error [0-9]+$|\*\*\* \[' /tmp/buildstep.txt | tail -30

echo "--- fatal / ld / undefined ---"
grep -nE 'fatal error|Undefined symbols|ld: |duplicate symbol|No rule to make target|unknown target|not found' /tmp/buildstep.txt | tail -30

echo "--- last 25 non-warning lines ---"
grep -vE 'warning:|note:|\^|^ *$|In file included|#define|__auto_type|_os_atomic' /tmp/buildstep.txt | tail -25
