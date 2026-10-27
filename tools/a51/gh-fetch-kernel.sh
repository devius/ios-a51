#!/bin/bash
# Wait for the newest xnu run and fetch its xnu-kernel artifact into the repo.
#
#   gh-fetch-kernel.sh [RUN_ID]
#
# Prints the run's Build diagnostics, the LSE check, the artifact listing, and
# copies kernel.development to out/kernel.development (the path
# tools/a51/make-boot.ps1 -Kernel expects).
set -uo pipefail
TOK=$(tr -d '\r\n' < /mnt/g/a51-port/toolchain/gh_token.txt)
OWNER=nickdemon22
NAME=ios-a51
REPO=/mnt/g/a51-port/ios-a51
RUN=${1:-}

if [ -z "$RUN" ]; then
  for _ in $(seq 1 80); do
    curl -s -H "Authorization: Bearer $TOK" \
      "https://api.github.com/repos/$OWNER/$NAME/actions/runs?per_page=1" -o /tmp/r.json
    RUN=$(python3 -c "
import json
print(json.load(open('/tmp/r.json'))['workflow_runs'][0]['id'])")
    STATUS=$(curl -s -H "Authorization: Bearer $TOK" \
      "https://api.github.com/repos/$OWNER/$NAME/actions/runs/$RUN" |
      python3 -c "import json,sys;print(json.load(sys.stdin)['status'])")
    [ "$STATUS" = completed ] && break
    sleep 20
  done
  echo "run $RUN $STATUS"
else
  for _ in $(seq 1 160); do
    curl -s -H "Authorization: Bearer $TOK" \
      "https://api.github.com/repos/$OWNER/$NAME/actions/runs/$RUN" -o /tmp/r.json
    read -r STATUS CONCL <<< "$(python3 -c "
import json
r = json.load(open('/tmp/r.json'))
print(r['status'], r['conclusion'])")"
    [ "$STATUS" = completed ] && break
    sleep 20
  done
  echo "run $RUN $STATUS/$CONCL"
fi

curl -s -H "Authorization: Bearer $TOK" \
  "https://api.github.com/repos/$OWNER/$NAME/actions/runs/$RUN/jobs" -o /tmp/j.json
jid=$(python3 -c "import json;print(json.load(open('/tmp/j.json'))['jobs'][0]['id'])")
LOG=$HOME/a51-new-$RUN.log
curl -sL -H "Authorization: Bearer $TOK" \
  "https://api.github.com/repos/$OWNER/$NAME/actions/jobs/$jid/logs" -o "$LOG"
echo "log: $LOG ($(wc -c < "$LOG") bytes)"

echo
echo "=== Make errors / tail / fakeroot (as printed by the Build step) ==="
for g in 'make errors' 'tail' 'kernel artifacts'; do
  echo "--- $g"
  sed -n "/::group::${g}/,/::endgroup::/p" "$LOG" | sed -E 's/^[0-9T:.Z-]+ //' | sed '1d;$d' | head -40
done

echo
echo "=== LSE report ==="
sed -n '/::group::LSE/,/::endgroup::/p' "$LOG" | sed -E 's/^[0-9T:.Z-]+ //' | head -10
grep -n 'LSE instructions:' "$LOG" | sed -E 's/^[0-9]+:[0-9T:.Z-]+ //' | tail -5

echo
echo "=== artifacts ==="
curl -s -H "Authorization: Bearer $TOK" \
  "https://api.github.com/repos/$OWNER/$NAME/actions/runs/$RUN/artifacts" -o /tmp/arts.json
python3 - <<'PY'
import json
d = json.load(open('/tmp/arts.json'))
for a in d.get('artifacts', []):
    print(f"  {a['id']} {a['name']} {a['size_in_bytes']} bytes")
PY
aid=$(python3 -c "
import json
d = json.load(open('/tmp/arts.json'))
print(next((a['id'] for a in d.get('artifacts', []) if a['name'] == 'xnu-kernel'), ''))")
if [ -z "$aid" ]; then echo "no xnu-kernel artifact"; exit 1; fi

rm -rf "$HOME/kern-$RUN" && mkdir -p "$HOME/kern-$RUN"
curl -sL -H "Authorization: Bearer $TOK" -H 'Accept: application/vnd.github+json' \
  "https://api.github.com/repos/$OWNER/$NAME/actions/artifacts/$aid/zip" -o /tmp/kern.zip
python3 - "$HOME/kern-$RUN" <<'PY'
import sys, zipfile
with zipfile.ZipFile('/tmp/kern.zip') as z:
    for n in z.namelist():
        print('  entry:', n)
    z.extractall(sys.argv[1])
PY
ls -l "$HOME/kern-$RUN"
sha256sum "$HOME"/kern-$RUN/kernel.* 2>/dev/null

K=$HOME/kern-$RUN/kernel.development
if [ -f "$K" ]; then
  mkdir -p "$REPO/out"
  cp "$K" "$REPO/out/kernel.development"
  echo "copied -> $REPO/out/kernel.development"
  echo "size $(wc -c < "$REPO/out/kernel.development") ; sha256 $(sha256sum "$REPO/out/kernel.development" | cut -d' ' -f1)"
else
  echo "kernel.development not in the artifact"; ls -l "$HOME/kern-$RUN"
fi
