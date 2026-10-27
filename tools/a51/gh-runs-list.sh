#!/bin/bash
TOK=$(tr -d '\r\n' < /mnt/g/a51-port/toolchain/gh_token.txt)
curl -s -H "Authorization: Bearer $TOK" \
  "https://api.github.com/repos/nickdemon22/ios-a51/actions/runs?per_page=10" -o /tmp/runs.json
python3 - <<'PY'
import json
d = json.load(open('/tmp/runs.json'))
print('total_count', d.get('total_count'))
for r in d.get('workflow_runs', []):
    print(f"{r['id']} {r['name']} event={r['event']} {r['status']}/{r['conclusion']} "
          f"branch={r['head_branch']} sha={r['head_sha'][:8]} "
          f"created={r['created_at']} updated={r['updated_at']} "
          f"run_attempt={r.get('run_attempt')}")
PY
