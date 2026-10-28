#!/bin/bash
# Checks for gpu/eagl (Bergamota's EAGL shim via the S7 port) on the A51:
# no S7 names or install paths outside attribution lines, the A51 rpath,
# Reduce Transparency for backboardd (no black blur backgrounds), the MIT
# notice kept.
set -uo pipefail
here=$(cd "$(dirname "$0")" && pwd)
ok=0
fail() { echo "FAIL: $*"; ok=1; }
[[ -f $here/NOTICE.md && -f $here/build-eagl.sh && -f $here/src/eagl.m ]] || { echo "FAIL: shim sources missing"; exit 1; }
left=$(grep -rn -E 'herolte|HEROLTE|/private/var/herolte|Galaxy S7.s' "$here" | grep -v -e 'check-eagl.sh' -e 'S7 port' -e 'NOTICE.md' || true)
[[ -z $left ]] || fail "S7 leftovers: $left"
grep -q -- '-Wl,-rpath,/private/var/root/gpu/lib' "$here/build-eagl.sh" || fail "rpath is not /private/var/root/gpu/lib"
grep -q 'EnhancedBackgroundContrastEnabled' "$here/src/hero_backboardd.c" || fail "no Reduce Transparency in hero_backboardd.c"
grep -q 'MIT' "$here/NOTICE.md" || fail "NOTICE.md lost the MIT notice"
[[ $ok == 0 ]] && echo "eagl checks passed"
exit $ok
