#!/bin/bash
# What can this token actually do? List the repos it can see with their
# visibility and permissions, and probe whether a fork can be created.
set -uo pipefail
TOK=$(tr -d '\r\n' < /mnt/g/a51-port/toolchain/gh_token.txt)
api() { curl -s -o /tmp/gh_body -w '%{http_code}' -H "Authorization: Bearer $TOK" \
        -H 'Accept: application/vnd.github+json' -H 'X-GitHub-Api-Version: 2022-11-28' "$@"; }

echo "== repositories visible to the token =="
code=$(api "https://api.github.com/user/repos?affiliation=owner&per_page=100")
echo "GET /user/repos -> $code"
python3 - <<'PY'
import json
try:
    d = json.load(open('/tmp/gh_body'))
except Exception:
    print(open('/tmp/gh_body').read()[:300]); raise SystemExit
if isinstance(d, dict):
    print(' ', d.get('message')); raise SystemExit
for r in sorted(d, key=lambda x: x['name']):
    p = r.get('permissions') or {}
    print(f"  {r['full_name']:<40} private={r['private']!s:<5} "
          f"push={p.get('push')} actions={r.get('has_actions')} "
          f"default={r.get('default_branch')}")
PY

echo
echo "== can the token read the donor repo's workflows? =="
echo "  GET /repos/Floppikrob/ios-galaxy-s8/actions/workflows -> $(api https://api.github.com/repos/Floppikrob/ios-galaxy-s8/actions/workflows)"
python3 -c "import json;d=json.load(open('/tmp/gh_body'));print('   total:',d.get('total_count'));[print('   -',w['name'],w['state'],w['path']) for w in d.get('workflows',[])]" 2>/dev/null

echo
echo "== probe: fork the donor repo (creates nothing if denied) =="
code=$(api -X POST https://api.github.com/repos/Floppikrob/ios-galaxy-s8/forks -d '{}')
echo "POST /forks -> $code"
head -c 300 /tmp/gh_body; echo
