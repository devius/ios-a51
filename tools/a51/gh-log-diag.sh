#!/bin/bash
# Print the real failure from a downloaded job log.
L=$(ls -S /tmp/job-*.log 2>/dev/null | head -1)
echo "log: $L ($(wc -l < "$L") lines)"

echo "--- error: diagnostics ---"
grep -n 'error:' "$L" | tail -30

echo "--- make/ld failures ---"
grep -nE 'make(\[[0-9]+\])?: \*\*\*|ninja: build stopped|The following build commands failed|\*\* BUILD FAILED \*\*|clang: error' "$L" | tail -20

echo "--- last 40 lines ---"
tail -40 "$L"
