#!/bin/bash
# Regenerate 0125 with LF endings, confirm the encoding, then re-apply the whole
# patch series to a pristine xnu-8796.141.3 tree and re-check that the two routes
# (0125 patch vs apply-a51.py) still agree byte for byte.
set -uo pipefail
REPO=/mnt/g/a51-port/ios-a51
cd "$REPO/tools/a51" || exit 1

echo "== regenerate 0125 =="
python3 mkpatch0125.py || exit 1
file -b "$REPO/xnu/patches/0125-a51-exynos9611.patch"
python3 verify-patch0125.py || exit 1

echo
echo "== normalise .gitignore line endings =="
python3 - <<'PY'
from pathlib import Path
p = Path('/mnt/g/a51-port/ios-a51/.gitignore')
b = p.read_bytes().replace(b'\r\n', b'\n')
p.write_bytes(b)
print('  .gitignore:', len(b), 'bytes, LF only')
PY

echo
echo "== rebuild both trees from scratch =="
tr -d '\r' < "$REPO/tools/dreamlte/prep-xnu-tree.sh" > /tmp/prep.sh
rm -rf /home/nickolay/xnuwork
bash /tmp/prep.sh "$REPO/xnu/patches" /home/nickolay/xnuwork 2>&1 |
    grep -E 'SKIP|FIXUP|tree=' | tail -8

echo
tr -d '\r' < "$REPO/tools/a51/verify-board-routes.sh" > /tmp/vbr.sh
bash /tmp/vbr.sh 2>&1 | tail -12

echo
echo "== resulting board block in the 0125 tree =="
sed -n '27,40p' /home/nickolay/xnuwork/xnu/pexpert/pexpert/arm64/A5XELTE.h
echo "..."
grep -n 'UFS_ADT_NODE\|UFS_DEFAULT_PART' /home/nickolay/xnuwork/xnu/bsd/dev/sweet_ufs.c | head -4
