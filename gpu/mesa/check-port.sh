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
echo "port checks passed"
