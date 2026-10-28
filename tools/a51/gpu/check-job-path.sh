#!/bin/bash
# Source checks for bsd/dev/a51_gpu.c's job path (final review 2026-10-29):
#  1. with flush reduction (JS_CONFIG bit 14) every job writes JS_FLUSH_ID_NEXT
#     (slot + 0x70) from GPU_LATEST_FLUSH_ID (0x38), as Panfrost does;
#  2. a51_gpu_run() resets a51_last_js_status on entry, so an early return
#     (MMU UPDATE timeout) cannot report the previous job's status.
#   check-job-path.sh XNU_TREE
set -euo pipefail
f=${1:?usage: $0 XNU_TREE}/bsd/dev/a51_gpu.c
run=$(sed -n '/^a51_gpu_run(/,/^}/p' "$f")
ok=0
grep -q 'JS_FLUSH_ID_NEXT.*GPU_LATEST_FLUSH_ID' <<<"$run" || { echo "FAIL: no JS_FLUSH_ID_NEXT write in a51_gpu_run"; ok=1; }
grep -qE '#define JS_FLUSH_ID_NEXT +0x70' "$f" || { echo "FAIL: JS_FLUSH_ID_NEXT is not slot + 0x70"; ok=1; }
grep -qE '#define GPU_LATEST_FLUSH_ID +0x038' "$f" || { echo "FAIL: GPU_LATEST_FLUSH_ID is not 0x038"; ok=1; }
first=$(grep -n -m1 'a51_last_js_status' <<<"$run" | cut -d: -f1)
update=$(grep -n -m1 'AS_COMMAND_UPDATE' <<<"$run" | cut -d: -f1)
[[ -n $first && $first -lt $update ]] && grep -m1 'a51_last_js_status' <<<"$run" | grep -q '= ~0u' ||
	{ echo "FAIL: a51_last_js_status not reset to ~0u before the MMU UPDATE"; ok=1; }
[[ $ok == 0 ]] && echo "job path checks passed"
exit $ok
