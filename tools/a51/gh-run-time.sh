#!/bin/bash
# Are the last build lines contemporaneous with the step's end (log complete),
# or do they stop early (log truncated)?
L=$HOME/a51-job-40452629749.log
s=$(grep -n '\[group\]Run bash build.sh' "$L" | head -1 | cut -d: -f1)
e=$(grep -n '##\[error\]Process completed' "$L" | head -1 | cut -d: -f1)
echo "step $s..$e"
echo "--- last 5 timestamps of the step ---"
sed -n "${s},${e}p" "$L" | grep -oE '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:.]+Z' | tail -5
echo "--- first 3 ---"
sed -n "${s},${e}p" "$L" | grep -oE '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:.]+Z' | head -3
echo "--- distribution of timestamps per minute ---"
sed -n "${s},${e}p" "$L" | grep -oE '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}' | sort | uniq -c
