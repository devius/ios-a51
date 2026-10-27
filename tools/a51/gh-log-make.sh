#!/bin/bash
# Where does the xnu make start, and what is printed after it?
L=$(ls -S /tmp/job-*.log 2>/dev/null | head -1)
sed -n '357,124276p' "$L" | sed -E 's/^[0-9T:.Z-]+ //' > /tmp/buildstep.txt

echo "--- make invocations / target configs ---"
grep -n 'TARGET_CONFIGS\|MACHINE_CONFIG=\|make install\|Building xnu\|Building kernel' /tmp/buildstep.txt | head -20

echo
echo "--- dxb script's own lines (colored [info]/[error]/[warning]) ---"
grep -nE '\[(info|error|warning|success)\]|^\s*[│┃╭╰─]' /tmp/buildstep.txt | tail -30

echo
echo "--- lines after the first fasttrap.c mention ---"
first=$(grep -n 'fasttrap.c' /tmp/buildstep.txt | head -1 | cut -d: -f1)
echo "first fasttrap at $first"
sed -n "$((first-5)),$((first+15))p" /tmp/buildstep.txt
