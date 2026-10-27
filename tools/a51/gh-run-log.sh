#!/bin/bash
# Download the log of a workflow run's jobs and print the failing part.
#   gh-run-log.sh [RUN_ID] [PATTERN]
set -uo pipefail
TOK=$(tr -d '\r\n' < /mnt/g/a51-port/toolchain/gh_token.txt)
OWNER=nickdemon22
NAME=ios-a51
run_id=${1:-}
pat=${2:-}

if [ -z "$run_id" ]; then
  curl -s -H "Authorization: Bearer $TOK" \
    "https://api.github.com/repos/$OWNER/$NAME/actions/runs?per_page=1" -o /tmp/runs.json
  run_id=$(python3 -c "import json;print(json.load(open('/tmp/runs.json'))['workflow_runs'][0]['id'])")
fi
echo "run $run_id"

curl -s -H "Authorization: Bearer $TOK" \
  "https://api.github.com/repos/$OWNER/$NAME/actions/runs/$run_id/jobs" -o /tmp/jobs.json
python3 - <<'PY'
import json
d = json.load(open('/tmp/jobs.json'))
for j in d.get('jobs', []):
    print(j['id'], j['name'], j['conclusion'])
PY

for jid in $(python3 -c "
import json
d = json.load(open('/tmp/jobs.json'))
print(' '.join(str(j['id']) for j in d.get('jobs', [])))"); do
  echo "== log for job $jid =="
  curl -sL -H "Authorization: Bearer $TOK" \
    "https://api.github.com/repos/$OWNER/$NAME/actions/jobs/$jid/logs" \
    -o "/tmp/job-$jid.log"
  wc -l "/tmp/job-$jid.log"
done

LOG=$(ls -S /tmp/job-*.log | head -1)
echo "== log: $LOG =="
if [ -n "$pat" ]; then
  grep -n -- "$pat" "$LOG" | head -80
else
  grep -n -i -E 'error|fatal|failed|undefined|No such file' "$LOG" | head -80
fi
