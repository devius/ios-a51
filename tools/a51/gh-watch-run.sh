#!/bin/bash
# Watch the xnu workflow run and, when it finishes, download the kernel
# artifact into xnu/out-a51/ (gitignored). The token is never printed.
set -uo pipefail
REPO=/mnt/g/a51-port/ios-a51
TOK=$(tr -d '\r\n' < /mnt/g/a51-port/toolchain/gh_token.txt)
OWNER=nickdemon22
NAME=ios-a51
OUT="$REPO/xnu/out-a51"

api() { curl -s -o /tmp/gh_body -w '%{http_code}' -H "Authorization: Bearer $TOK" \
        -H 'Accept: application/vnd.github+json' -H 'X-GitHub-Api-Version: 2022-11-28' "$@"; }

run_id=${1:-}
if [ -z "$run_id" ]; then
  api "https://api.github.com/repos/$OWNER/$NAME/actions/runs?per_page=1" >/dev/null
  run_id=$(python3 -c "import json;print(json.load(open('/tmp/gh_body'))['workflow_runs'][0]['id'])")
fi
echo "watching run $run_id"

prev=""
for i in $(seq 1 90); do
  api "https://api.github.com/repos/$OWNER/$NAME/actions/runs/$run_id" >/dev/null
  read -r status conclusion <<< "$(python3 -c "
import json
d = json.load(open('/tmp/gh_body'))
print(d.get('status'), d.get('conclusion'))")"
  if [ "$status/$conclusion" != "$prev" ]; then
    echo "[$(date +%H:%M:%S)] status=$status conclusion=$conclusion"
    prev="$status/$conclusion"
  fi
  if [ "$status" = completed ]; then
    break
  fi
  sleep 30
done

echo
echo "== jobs =="
api "https://api.github.com/repos/$OWNER/$NAME/actions/runs/$run_id/jobs" >/dev/null
python3 - <<'PY'
import json
d = json.load(open('/tmp/gh_body'))
for j in d.get('jobs', []):
    print(f"  {j['name']}: {j['status']}/{j['conclusion']}")
    for s in j.get('steps', []):
        mark = 'ok ' if s['conclusion'] == 'success' else ('ERR' if s['conclusion'] == 'failure' else '   ')
        print(f"    {mark} {s['name']}: {s['status']}/{s['conclusion']}")
PY

echo
echo "== artifacts =="
api "https://api.github.com/repos/$OWNER/$NAME/actions/runs/$run_id/artifacts?per_page=20" >/dev/null
python3 - <<'PY'
import json
d = json.load(open('/tmp/gh_body'))
for a in d.get('artifacts', []):
    print(f"  {a['id']} {a['name']} {a['size_in_bytes']} bytes expired={a['expired']}")
PY

mkdir -p "$OUT"
for want in xnu-kernel; do
  aid=$(python3 - "$want" <<'PY'
import json, sys
d = json.load(open('/tmp/gh_body'))
for a in d.get('artifacts', []):
    if a['name'] == sys.argv[1] and not a['expired']:
        print(a['id']); break
PY
)
  if [ -z "$aid" ]; then echo "artifact $want not found"; continue; fi
  echo
  echo "== downloading $want (artifact $aid) =="
  curl -sL -H "Authorization: Bearer $TOK" -H 'Accept: application/vnd.github+json' \
    "https://api.github.com/repos/$OWNER/$NAME/actions/artifacts/$aid/zip" -o /tmp/artifact.zip
  ls -l /tmp/artifact.zip
  rm -rf "$OUT" && mkdir -p "$OUT"
  python3 - "$OUT" <<'PY'
import sys, zipfile
with zipfile.ZipFile('/tmp/artifact.zip') as z:
    z.extractall(sys.argv[1])
    print(f'  extracted {len(z.namelist())} entries')
PY
  ls -la "$OUT"
  echo
  echo "== kernels =="
  find "$OUT" -maxdepth 2 -type f -name 'kernel*' -exec ls -l {} \; -exec sha256sum {} \;
done
