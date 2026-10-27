#!/bin/bash
# Secret-scanner hygiene: the detection scripts themselves must not contain
# literal token prefixes, or every scanner (and GitHub's push protection) flags
# the repo. Rewrite the patterns so they still match real tokens but are not
# themselves matches: ghp_ -> gh[p]_, github_pat_ -> github[_]pat_.
set -uo pipefail
cd /mnt/g/a51-port/ios-a51 || exit 1
for f in tools/a51/prepublish-check.sh tools/a51/gh-token-check.sh \
         tools/a51/gh-capabilities.sh tools/a51/gh-token-probe.sh \
         tools/a51/gh-commit.sh tools/a51/gh-publish.sh tools/a51/gh-push-branch.sh; do
    [ -f "$f" ] || continue
    before=$(md5sum "$f" | cut -d' ' -f1)
    sed -i -E 's/ghp_\[/gh[p]_[/g; s/\bghp_/gh[p]_/g; s/github_pat_/github[_]pat_/g' "$f"
    # undo double-rewrites inside already-safe classes
    sed -i -E 's/gh\[p\]_\[/gh[p]_[/g' "$f"
    after=$(md5sum "$f" | cut -d' ' -f1)
    if [ "$before" != "$after" ]; then echo "  rewrote $f"; else echo "  unchanged $f"; fi
done
echo
echo "== residual literal prefixes in tracked scripts =="
grep -rn --exclude-dir=.git -E 'ghp_[A-Za-z0-9]{10,}|github_pat_[A-Za-z0-9_]{10,}' . || echo "  none"
