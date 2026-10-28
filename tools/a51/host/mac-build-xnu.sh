#!/bin/bash
# Build the A51 XNU kernel on a Mac exactly as CI does (.github/workflows/xnu.yml):
# blacktop/darwin-xnu-build at the pinned DXB_SHA, our xnu/patches/*.patch and
# *.sh next to blacktop's, the Cortex-A53 code-generation flags, and
#   MACOS_VERSION=13.5 KERNEL_CONFIG=DEVELOPMENT MACHINE_CONFIG=A5XELTE.
#   mac-build-xnu.sh SRC          (SRC holds patches/ and xnu.yml, from mac-kernel.sh)
# Output: SRC/../out/kernel.development.a5xelte (+ SHA256SUMS, build.log).
# The first run downloads Apple's KDK 13.5 (dortania mirror) and installs it
# with sudo: run that one in a terminal (ssh -t). Needs setup-mac-build.sh first.
set -euo pipefail
src=$(cd "${1:?usage: $0 SRC}" && pwd)
work=$(dirname "$src")
export PATH=/usr/local/bin:$PATH
dxb_sha=$(sed -n 's/^ *DXB_SHA: *//p' "$src/xnu.yml")
[[ -n $dxb_sha ]] || { echo "no DXB_SHA in $src/xnu.yml"; exit 1; }

cd "$work"
rm -rf dxb out
git init -q dxb
git -C dxb fetch -q --depth 1 https://github.com/blacktop/darwin-xnu-build "$dxb_sha"
git -C dxb checkout -q FETCH_HEAD
cp "$src"/patches/*.patch "$src"/patches/*.sh dxb/patches/
# As CI: ARMv8.0 Cortex-A53 code generation (no LSE atomics), plain arm64.
sed -i '' "s/ARCHS=\"x86_64 arm64e\" VALID_ARCHS=\"x86_64 arm64e\"/ARCHS=arm64 VALID_ARCHS=arm64 OTHER_CFLAGS='-mkernel -nostdinc -Wno-packed -mcpu=cortex-a53 -march=armv8-a+crypto'/" dxb/build.sh
grep -q "VALID_ARCHS=arm64 OTHER_CFLAGS='-mkernel -nostdinc -Wno-packed -mcpu=cortex-a53" dxb/build.sh

echo "building (log: $work/build.log), started $(date +%T)"
set +e
(cd dxb && MACOS_VERSION=13.5 KERNEL_CONFIG=DEVELOPMENT MACHINE_CONFIG=A5XELTE MAKEFLAGS=-k \
	bash build.sh > ../build.log 2>&1)
rc=$?
set -e
echo "build.sh exit=$rc at $(date +%T)"
echo "-- our patches not applied (must be empty):"
grep -E 'Skipping patch .*/[0-9]{4}-' build.log || true
echo "-- errors:"
grep -nE 'error:|fatal error|Error [0-9]+|\*\*\* |ld: [^w]|Undefined symbols|No rule to make' build.log |
	grep -v 'warning:' | tail -40 || true

mkdir -p out
cp -R dxb/fakeroot/System/Library/Kernels/. out/ 2>/dev/null || true
cp build.log out/
k=out/kernel.development.a5xelte
if [[ -f $k ]]; then
	(cd out && shasum -a 256 kernel.* > SHA256SUMS)
	lse=$(xcrun llvm-objdump -d --no-show-raw-insn "$k" | grep -cE '	(cas|casa|casal|casl|casp|ldadd|ldclr|ldeor|ldset|ldsmax|ldsmin|ldumax|ldumin|stadd|stclr|steor|stset|stsmax|stsmin|stumax|stumin|swp)[a-z]*	' || true)
	echo "kernel: $(ls -l "$k" | awk '{print $5}') bytes, LSE instructions: $lse"
else
	echo "no kernel produced"
	exit 1
fi
