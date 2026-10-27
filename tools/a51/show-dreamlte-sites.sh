#!/bin/bash
# Show every DREAMLTE-guarded site in the patched tree so the A51 port can
# decide, per site, whether the S8 code path applies or needs A51 values.
set -uo pipefail
cd ~/xnuwork/xnu
for hit in $(grep -rn 'defined(DREAMLTE)' --include='*.c' --include='*.cpp' \
             --include='*.h' --include='*.s' . | cut -d: -f1,2); do
    f=${hit%%:*}; n=${hit##*:}
    echo "=============================================================="
    echo "### $f:$n"
    start=$((n - 4)); [ $start -lt 1 ] && start=1
    sed -n "${start},$((n + 18))p" "$f"
done
