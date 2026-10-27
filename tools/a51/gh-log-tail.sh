#!/bin/bash
# Tail of the failing build step.
L=$(ls -S /tmp/job-*.log 2>/dev/null | head -1)
sed -n '124120,124276p' "$L" | sed -E 's/^[0-9T:.Z-]+ //'
