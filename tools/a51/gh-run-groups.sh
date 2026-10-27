#!/bin/bash
# Show the Diagnostics groups from the latest run and download build-log.
set -uo pipefail
TOK=$(tr -d '\r\n' < /mnt/g/a51-port/toolchain/gh_token.txt)
OWNER=nickdemon22
NAME=ios-a51
RUN=$1
LOG=$HOME/a51-new-$RUN.log

echo "=== groups in the job log ==="
grep -n '##\[group\]\|##\[endgroup\]\|build.sh exit=\|disk after' "$LOG" | head -20

echo
echo "=== everything after 'build.sh exit=' ==="
n=$(grep -n 'build.sh exit=' "$LOG" | head -1 | cut -d: -f1)
sed -n "${n},999p" "$LOG" | sed -E 's/^[0-9T:.Z-]+ //' | head -80

echo
echo "=== download build-log artifact ==="
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
print(next((a['id'] for a in d.get('artifacts', []) if a['name'] == 'build-log'), ''))")
if [ -n "$aid" ]; then
  curl -sL -H "Authorization: Bearer $TOK" -H 'Accept: application/vnd.github+json' \
    "https://api.github.com/repos/$OWNER/$NAME/actions/artifacts/$aid/zip" -o /tmp/build-log.zip
  ls -l /tmp/build-log.zip
  rm -rf "$HOME/buildlog" && mkdir -p "$HOME/buildlog"
  python3 - "$HOME/buildlog" <<'PY'
import sys, zipfile
with zipfile.ZipFile('/tmp/build-log.zip') as z:
    z.extractall(sys.argv[1])
    print('entries:', z.namelist())
PY
  ls -l "$HOME/buildlog"
fi
