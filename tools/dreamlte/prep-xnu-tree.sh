#!/bin/bash
# Recreate the patched source tree locally: xnu-8796.141.3 + PATCH_DIR/*.patch
# in lexical order, one git commit per patch (message = patch file name).
#
# Several A5XELTE patches are zero-context (-U0), carry a stray "xnu/" path
# prefix or have wrong hunk line counts, so plain `git apply` (what
# blacktop/darwin-xnu-build uses) rejects them. Fallbacks, in order:
#   git apply; git apply --unidiff-zero; patch -p1; patch -p2;
#   patch -p1 after recounting hunk headers.
# The *.sh staging scripts need macOS (xcrun) and are not run, so patches
# against staged trees (bsd/sweet_hfs/...) are reported as skipped.
# Usage: prep-xnu-tree.sh PATCH_DIR WORK_DIR
set -uo pipefail
patches=$(realpath "$1")
work=$2
mkdir -p "$work"
if [[ ! -d "$work/xnu-orig/.git" ]]; then
	git clone -q --depth 1 --branch xnu-8796.141.3 https://github.com/apple-oss-distributions/xnu.git "$work/xnu-orig" || exit 1
fi
rm -rf "$work/xnu"
cp -a "$work/xnu-orig" "$work/xnu"
cd "$work/xnu"
git config user.email local@s8
git config user.name local
git tag -f base >/dev/null

recount() {	# rewrite @@ counts from the hunk bodies
	python3 - "$1" <<'PY'
import re, sys
lines = open(sys.argv[1]).read().split('\n')
out, i = [], 0
while i < len(lines):
    m = re.match(r'^@@ -(\d+)(?:,\d+)? \+(\d+)(?:,\d+)? @@(.*)$', lines[i])
    if not m:
        out.append(lines[i]); i += 1; continue
    j, old, new = i + 1, 0, 0
    while j < len(lines) and not lines[j].startswith(('@@', '--- ', 'diff ')):
        t = lines[j]
        if t.startswith('+'): new += 1
        elif t.startswith('-'): old += 1
        elif t.startswith(' ') or t == '': old += 1; new += 1
        j += 1
    # a trailing empty line at the end of file is not part of the hunk
    while j > i + 1 and lines[j - 1] == '' and (j == len(lines) or lines[j].startswith(('--- ', 'diff '))):
        j -= 1; old -= 1; new -= 1
    out.append(f'@@ -{m.group(1)},{old} +{m.group(2)},{new} @@{m.group(3)}')
    out.extend(lines[i + 1:j]); i = j
sys.stdout.write('\n'.join(out))
PY
}

for p in "$patches"/*.patch; do
	n=$(basename "$p")
	how=""
	if [[ $n == 0112-a5xelte-two-core-smp.patch ]]; then
		# Its timebase hunk spells ACNTVCT_EL0 by encoding (S3_4_c15_c10_6);
		# xnu-8796.141.3 uses the name. Same register, same instruction.
		fixed=$(mktemp)
		sed 's/S3_4_c15_c10_6/ACNTVCT_EL0/' "$p" > "$fixed"
		p=$fixed
	fi
	if git apply --check "$p" 2>/dev/null; then git apply "$p" && how=git
	elif git apply --check --unidiff-zero "$p" 2>/dev/null; then git apply --unidiff-zero "$p" && how=git-u0
	elif patch -p1 --dry-run -s -f -N < "$p" >/dev/null 2>&1; then patch -p1 -s -f -N < "$p" && how=patch-p1
	elif patch -p2 --dry-run -s -f -N < "$p" >/dev/null 2>&1; then patch -p2 -s -f -N < "$p" && how=patch-p2
	else
		fixed=$(mktemp); recount "$p" > "$fixed"
		if patch -p1 --dry-run -s -f -N < "$fixed" >/dev/null 2>&1; then patch -p1 -s -f -N < "$fixed" && how=recount
		fi
		rm -f "$fixed"
	fi
	find . -name '*.orig' -newer "$p" -delete 2>/dev/null
	if [[ -z $how ]]; then
		echo "SKIP  $n"
		continue
	fi
	[[ $how == git ]] || echo "FIXUP $n ($how)"
	git add -A >/dev/null
	git commit -qm "$n" --allow-empty
done
echo "tree=$work/xnu commits=$(git rev-list --count base..HEAD)"
