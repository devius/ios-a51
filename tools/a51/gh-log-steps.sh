#!/bin/bash
# The Build step's own failure markers.
L=$(ls -S /tmp/job-*.log 2>/dev/null | head -1)
echo "log: $L"
echo "--- ##[error] lines ---"
grep -n '##\[error\]' "$L" | head -40
echo
echo "--- step boundaries ---"
grep -n '##\[group\]' "$L" | head -40
echo
echo "--- exit codes / failure summary ---"
grep -nE 'Process completed with exit code|BUILD (FAILED|SUCCEEDED)|Error: Process' "$L" | head -20
