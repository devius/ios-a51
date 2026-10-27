#!/bin/bash
# Pre-publish hygiene check: line endings, UTF-8 validity, and any secret or
# device-identifying strings that must not go into a public repository.
set -uo pipefail
cd /mnt/g/a51-port/ios-a51 || exit 1

echo "== encoding and line endings of the files touched this session =="
for f in A51_PROGRESS.md .gitignore \
         tools/a51/apply-a51.py tools/a51/a51_board.py tools/a51/mkpatch0125.py \
         tools/a51/verify-patch0125.py tools/a51/mkboot.js tools/a51/fdtdump.py \
         tools/mkadt_a51.py tools/check-adt.py \
         shim/a51/main.c shim/a51/start.S shim/a51/a51.ld shim/a51/ufs_probe.c \
         xnu/patches/0125-a51-exynos9611.patch; do
    [ -f "$f" ] || { printf '%-52s MISSING\n' "$f"; continue; }
    enc=$(file -b "$f")
    printf '%-52s %s\n' "$f" "$enc"
done

echo
echo "== CRLF files (would break git apply in CI) =="
crlf=$(grep -rlU $'\r' --include='*.patch' --include='*.py' --include='*.c' \
       --include='*.h' --include='*.S' --include='*.sh' --include='*.js' . 2>/dev/null)
if [ -n "$crlf" ]; then echo "$crlf" | sed 's/^/  /'; else echo "  none"; fi

echo
echo "== invalid UTF-8 =="
find . -path ./.git -prune -o -type f \( -name '*.md' -o -name '*.py' -o -name '*.c' \
     -o -name '*.h' -o -name '*.S' -o -name '*.patch' -o -name '*.sh' -o -name '*.ps1' \
     -o -name '*.js' -o -name '*.ld' \) -print0 2>/dev/null |
  xargs -0 -r -I{} sh -c 'iconv -f utf-8 -t utf-8 "{}" >/dev/null 2>&1 || echo "  BAD: {}"'

echo
echo "== secret / identity scan =="
grep -rn --exclude-dir=.git --exclude-dir=backup --exclude-dir=research \
     -E 'ghp_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,}|RZ8[A-Z0-9]{8}' . |
     sed 's/\(ghp_\|github_pat_\)[A-Za-z0-9_]*/\1<redacted>/g' | head -20
echo "  (empty above = clean)"

echo
echo "== files git would publish (top-level sizes) =="
du -sh --exclude=.git --exclude=backup --exclude=research . 2>/dev/null
ls -la
