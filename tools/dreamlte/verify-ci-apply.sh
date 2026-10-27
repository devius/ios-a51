#!/bin/bash
# Simulate CI: xnu-8796.141.3 + (A5 patches overlaid with fixed ones) applied
# with plain `git apply` only, then compare with /root/s8/xnu.
# Usage: verify-ci-apply.sh A5_PATCH_DIR FIXED_DIR
set -euo pipefail
a5=$(realpath "$1"); fixed=$(realpath "$2")
tmp=/root/s8/ci-sim
rm -rf "$tmp"; mkdir -p "$tmp/patches"
cp "$a5"/*.patch "$tmp/patches/"
cp "$fixed"/*.patch "$tmp/patches/"
cp -a /root/s8/xnu-orig "$tmp/xnu"
cd "$tmp/xnu"
skipped=0
for p in "$tmp"/patches/*.patch; do
	if git apply --check "$p" 2>/dev/null; then git apply "$p"
	else echo "CI would skip: $(basename "$p")"; skipped=$((skipped + 1)); fi
done
echo "skipped=$skipped (expected 2: the staged-HFS patches 0031/0041)"
if diff -rq -x .git "$tmp/xnu" /root/s8/xnu; then echo "TREES IDENTICAL"; else echo "TREES DIFFER"; fi
