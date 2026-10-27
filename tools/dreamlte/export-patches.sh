#!/bin/bash
# After prep-xnu-tree.sh: apply the S8 layer as commit 0124 and export
# context patches (git diff of each commit) for every A5 patch that plain
# `git apply` rejects, plus 0124, into OUT_DIR.
# Usage: export-patches.sh OUT_DIR
set -euo pipefail
out=$(realpath "$1")
here=$(dirname "$(realpath "$0")")
mkdir -p "$out"
cd /root/s8/xnu
echo "== 0094/0095 results"
grep -n 'MACHINE_FLAGS_ARM64_A5XELTE' makedefs/MakeInc.def
grep -n '__ARM_PAN_AVAILABLE__' pexpert/pexpert/arm64/A5XELTE.h
python3 "$here/apply-dreamlte.py" .
git add -A
git commit -qm 0124-dreamlte-s8.patch
for name in 0094-a5xelte-cortex-a53-codegen.patch 0095-a5xelte-disable-pan.patch \
	0106-a5xelte-amfi-bridge.patch 0107-a5xelte-4k-unsigned-dyld-cache.patch \
	0108-a5xelte-userdata-write.patch 0112-a5xelte-two-core-smp.patch \
	0122-a5xelte-pmic-linux-transfer-sequence.patch 0124-dreamlte-s8.patch; do
	c=$(git log --format=%H --grep="^$name\$" -n 1)
	[[ -n $c ]] || { echo "no commit for $name" >&2; exit 1; }
	git diff --no-color --no-prefix "$c~1" "$c" | sed -e 's#^--- \([^/]\)#--- a/\1#' -e 's#^+++ \([^/]\)#+++ b/\1#' > "$out/$name"
	echo "exported $name ($(grep -c '^@@' "$out/$name") hunks)"
done
