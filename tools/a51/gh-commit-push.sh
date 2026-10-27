#!/bin/bash
# Commit the working tree and push it to nickdemon22/ios-a51 main, which
# triggers the xnu workflow. The token is never printed.
set -uo pipefail
REPO=/mnt/g/a51-port/ios-a51
TOK=$(tr -d '\r\n' < /mnt/g/a51-port/toolchain/gh_token.txt)
OWNER=nickdemon22
NAME=ios-a51

cd "$REPO" || exit 1
git add -A
if git diff --cached --quiet; then
  echo "nothing to commit"
else
  git commit -q -F - "$@" <<'MSG'
ci: capture the full kernel build log and print only diagnostics

Run 40452629749 died with exit code 2 after four minutes of kernel compiles
and its step log ended mid-warning, with not one diagnostic in it: the console
log is truncated from the end, which is where make prints its errors. The
Build step now redirects build.sh to build.log, prints only the make errors
and the tail, and uploads build.log as an artifact, so the next failure is
readable no matter how loud the -Wdeclaration-after-statement warnings get.
It also prints disk and RAM before/after, since a full disk would look
exactly like this (output simply stops).
MSG
fi
echo "HEAD: $(git rev-parse --short HEAD)"

git remote remove origin 2>/dev/null
git remote add origin "https://$OWNER:$TOK@github.com/$OWNER/$NAME.git"
git push -u origin main 2>&1 | sed -E "s#$TOK#<token>#g" | tail -3
git remote set-url origin "https://github.com/$OWNER/$NAME.git"

sleep 10
curl -s -H "Authorization: Bearer $TOK" \
  "https://api.github.com/repos/$OWNER/$NAME/actions/runs?per_page=3" -o /tmp/runs.json
python3 - <<'PY'
import json
d = json.load(open('/tmp/runs.json'))
for r in d.get('workflow_runs', []):
    print(f"run {r['id']} {r['status']}/{r['conclusion']} sha={r['head_sha'][:8]} {r['html_url']}")
PY
