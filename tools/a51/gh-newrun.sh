#!/bin/bash
# Report the state of the newest xnu run, and when it finishes print the
# Build step's diagnostic groups (make errors + tail).
TOK=$(tr -d '\r\n' < /mnt/g/a51-port/toolchain/gh_token.txt)
OWNER=nickdemon22
NAME=ios-a51
for i in $(seq 1 60); do
  curl -s -H "Authorization: Bearer $TOK" \
    "https://api.github.com/repos/$OWNER/$NAME/actions/runs?per_page=1" -o /tmp/r.json
  read -r id status concl <<< "$(python3 -c "
import json
r = json.load(open('/tmp/r.json'))['workflow_runs'][0]
print(r['id'], r['status'], r['conclusion'])")"
  if [ "$status" = completed ]; then break; fi
  sleep 30
done
echo "run $id $status/$concl"
curl -s -H "Authorization: Bearer $TOK" \
  "https://api.github.com/repos/$OWNER/$NAME/actions/runs/$id/jobs" -o /tmp/j.json
jid=$(python3 -c "import json;print(json.load(open('/tmp/j.json'))['jobs'][0]['id'])")
curl -sL -H "Authorization: Bearer $TOK" \
  "https://api.github.com/repos/$OWNER/$NAME/actions/jobs/$jid/logs" \
  -o "$HOME/a51-new-$id.log"
echo "log: $(wc -c < "$HOME/a51-new-$id.log") bytes"
echo
echo "=== build diagnostics printed by the step ==="
grep -n 'build.sh exit=\|disk after\|^::group::\|^::endgroup::' "$HOME/a51-new-$id.log" | head
sed -n '/::group::make errors/,/::endgroup::/p' "$HOME/a51-new-$id.log" | head -60
echo
sed -n '/::group::tail/,/::endgroup::/p' "$HOME/a51-new-$id.log" | tail -45
echo
sed -n '/::group::kernel artifacts/,/::endgroup::/p' "$HOME/a51-new-$id.log"
