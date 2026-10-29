#!/bin/bash
# Check gpu/metal against Chlorophyll at the commit in gpu/metal/UPSTREAM.
#   gpu/metal/check-vendor.sh [UPSTREAM_CHECKOUT]
# Every vendored file must equal upstream's, or be listed under "Changed files"
# in gpu/metal/NOTICE-A51.md (one "- path" line each, relative to gpu/metal).
# Files we added are listed there under "Added files". Exit 1 names each other difference.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
[ -d "$HERE/air" ] || { echo "gpu/metal/air missing"; exit 1; }
read -r URL COMMIT < "$HERE/UPSTREAM"
UP="${1:-}"
if [ -z "$UP" ]; then
  UP="$(mktemp -d)"; trap 'rm -rf "$UP"' EXIT
  timeout 300 git clone -q "$URL" "$UP"
fi
git -C "$UP" checkout -q "$COMMIT"
listed() { sed -n "/^## $1/,/^## /p" "$HERE/NOTICE-A51.md" | sed -n 's/^- `\{0,1\}\([^` ]*\)`\{0,1\}.*/\1/p'; }
CHANGED="$(listed 'Changed files')"; ADDED="$(listed 'Added files')"
bad=0
cd "$HERE"
while IFS= read -r f; do
  f="${f#./}"
  case "$f" in UPSTREAM|NOTICE-A51.md|check-vendor.sh) continue;; esac
  if grep -qxF "$f" <<<"$ADDED"; then continue; fi
  if [ ! -f "$UP/$f" ]; then echo "not upstream and not listed as added: $f"; bad=1; continue; fi
  if ! cmp -s "$f" "$UP/$f" && ! grep -qxF "$f" <<<"$CHANGED"; then echo "differs from upstream, not listed: $f"; bad=1; fi
done < <(find . -type f | sort)
exit $bad
