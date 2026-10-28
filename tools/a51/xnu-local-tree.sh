#!/bin/bash
# Build the patched xnu source tree that CI (.github/workflows/xnu.yml) compiles,
# so new kernel patches are made against exactly that tree.
#   tools/a51/xnu-local-tree.sh WORKDIR
# WORKDIR/xnu = xnu-8796.141.3 (macOS 13.5) + blacktop's patches (darwin-xnu-build
# at DXB_SHA) + xnu/patches/*.patch, in build.sh's order and with its rule: a
# patch that fails `git apply --check` is SKIPPED, not fatal. The stage scripts
# (xnu/patches/*.sh) run first, as in build.sh.
# The result is committed as "baseline"; make a new patch with
#   git -C WORKDIR/xnu diff > xnu/patches/01NN-name.patch
# and put a description above the first "diff --git" line, as the others have.
set -euo pipefail
work=${1:?usage: $0 WORKDIR}
repo=$(cd "$(dirname "$0")/../.." && pwd)
dxb_sha=$(sed -n 's/^ *DXB_SHA: *//p' "$repo/.github/workflows/xnu.yml")
xnu_tag=xnu-8796.141.3

mkdir -p "$work"
cd "$work"
rm -rf xnu dxb
git init -q dxb
git -C dxb fetch -q --depth 1 https://github.com/blacktop/darwin-xnu-build "$dxb_sha"
git -C dxb checkout -q FETCH_HEAD
cp "$repo"/xnu/patches/*.patch "$repo"/xnu/patches/*.sh dxb/patches/
git clone -q --depth 1 --branch "$xnu_tag" https://github.com/apple-oss-distributions/xnu.git xnu

applied=0 skipped=0
cd xnu
# build.sh runs patches/*.sh from the xnu root first (bsd/sweet_hfs, libpthread,
# bearssl); 0031 and 0041 patch the staged HFS. Steps that need the macOS SDK
# (xcrun) fail here; the sources they stage are what matters.
for s in ../dxb/patches/*.sh; do
	if MACHINE_CONFIG=A5XELTE MACOS_VERSION=13.5 KDKROOT=/nonexistent bash "$s" >/dev/null 2>&1; then
		echo "staged $(basename "$s")"
	else
		echo "stage script failed (SDK step?): $(basename "$s")"
	fi
done
for p in ../dxb/patches/*.patch; do
	if git apply --check "$p" 2>/dev/null; then
		git apply "$p"
		applied=$((applied + 1))
	else
		echo "skipped $(basename "$p")"
		skipped=$((skipped + 1))
	fi
done
git add -A
git -c user.name=local -c user.email=local@localhost commit -q -m baseline
echo "applied $applied skipped $skipped ($xnu_tag, dxb $dxb_sha)"
