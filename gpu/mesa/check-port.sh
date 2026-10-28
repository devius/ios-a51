#!/bin/bash
# Checks for gpu/mesa (the A51 port of the S7's Mesa layer), on the PC:
#  - no Galaxy S7 names or install paths left;
#  - patch-mesa.py applies to a clean mesa-25.0.7 tree (it asserts every edit
#    matches exactly once, so Mesa drift fails here, not in the build);
#  - osmesa-test.c is the SSH version and compiles against Mesa's headers.
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
cache=${XDG_CACHE_HOME:-$HOME/.cache}/a51-mesa
mkdir -p "$cache"

left=$(grep -rn -E 'herolte|HEROLTE|T880|Galaxy S7|/private/var/herolte' "$here" | grep -v -e 'check-port.sh' -e 'S7 port' || true)
[[ -z $left ]] || { echo "FAIL: S7 leftovers:"; echo "$left"; exit 1; }

[[ -d $cache/mesa-25.0.7 ]] || git clone -q --depth 1 --branch mesa-25.0.7 https://gitlab.freedesktop.org/mesa/mesa.git "$cache/mesa-25.0.7"
tree=$(mktemp -d)
trap 'rm -rf "$tree"' EXIT
cp -a "$cache/mesa-25.0.7/." "$tree/"
out=$(python3 "$here/patch-mesa.py" "$tree")
grep -q 'appended osmesa_hero.inc' <<<"$out" && grep -q 'copied hero_hw.c' <<<"$out" ||
	{ echo "FAIL: patch-mesa.py output:"; echo "$out"; exit 1; }

t=$here/osmesa-test.c
grep -q 'sleep(20)' "$t" && { echo "FAIL: osmesa-test.c still sleeps 20 s"; exit 1; }
grep -q 'ERR_PATH' "$t" && { echo "FAIL: osmesa-test.c still uses ERR_PATH"; exit 1; }
grep -q 'GL_RENDERER' "$t" && grep -q 'fps' "$t" || { echo "FAIL: osmesa-test.c lacks GL_RENDERER/fps"; exit 1; }
clang -fsyntax-only -Wall -Wno-format -I "$tree/include" "$t"
# Final review (2026-10-29): a failed GPU job must not pass silently.
grep -q 'herodrm_fault_count' "$here/herodrm.c" && grep -qE 'out\[0\].*fail\(EIO\)|fail\(EIO\).*out\[0\]' <(sed -n '/^submit(/,/^}/p' "$here/herodrm.c") ||
	{ echo "FAIL: herodrm submit() does not report a failed job (EIO + herodrm_fault_count)"; exit 1; }
grep -q 'herodrm_fault_count()' "$t" && grep -q 'rc = 3' "$t" ||
	{ echo "FAIL: osmesa-test does not exit 3 after GPU job faults"; exit 1; }
# A rebuild reuses build-mesa.sh's mesa/ tree: it must be reset before patching.
rebuild=$(mktemp -d)
cp -a "$cache/mesa-25.0.7/." "$rebuild/mesa/" 2>/dev/null || { mkdir -p "$rebuild/mesa"; cp -a "$cache/mesa-25.0.7/." "$rebuild/mesa/"; }
reset=$(grep -E 'git -C mesa (checkout|clean)' "$here/build-mesa.sh" | tr '\n' ';')
[[ -n $reset ]] || { echo "FAIL: build-mesa.sh does not reset mesa/ before patching"; rm -rf "$rebuild"; exit 1; }
for pass in 1 2; do
	(cd "$rebuild" && eval "$reset" && python3 "$here/patch-mesa.py" mesa >/dev/null) ||
		{ echo "FAIL: patch run $pass on a kept tree"; rm -rf "$rebuild"; exit 1; }
done
rm -rf "$rebuild"
echo "port checks passed"
