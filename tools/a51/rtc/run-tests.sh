#!/bin/bash
# Host test of bsd/dev/a51_rtc.c's date math and layout detection (patch 0150):
#   tools/a51/rtc/run-tests.sh XNU_TREE
set -euo pipefail
x=${1:?usage: $0 XNU_TREE}
t=$(mktemp -d)
trap 'rm -rf "$t"' EXIT
sed -n '/^static int64_t$/,/^}$/p;/^static uint64_t$/,/^}$/p' "$x/bsd/dev/a51_rtc.c" > "$t/fns.c"
cp "$(dirname "$0")/test_rtc.c" "$t/t.c"
cc -std=c11 -Wall -Wextra -Dbool=_Bool -o "$t/t" "$t/t.c"
"$t/t"
