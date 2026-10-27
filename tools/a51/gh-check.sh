#!/bin/bash
# Check that the GitHub token found in ~/A51_Project_Export/.git/config is still
# valid and what it can do. The token itself is never printed.
set -uo pipefail
TOK=$(git -C ~/A51_Project_Export remote get-url origin | sed -E 's#https://[^:]+:([^@]+)@.*#\1#')
echo "token length: ${#TOK} (value hidden)"

api() { curl -s -o /tmp/gh_body -w '%{http_code}' -H "Authorization: token $TOK" \
        -H 'Accept: application/vnd.github+json' "$@"; }

code=$(api https://api.github.com/user)
echo "GET /user -> $code"
python3 - <<'PY'
import json
try:
    d = json.load(open('/tmp/gh_body'))
except Exception as e:
    print('  unparsable body:', e); raise SystemExit
print('  login          :', d.get('login'))
print('  name           :', d.get('name'))
plan = d.get('plan') or {}
print('  plan           :', plan.get('name'), '| private repos:', plan.get('private_repos'))
print('  public repos   :', d.get('public_repos'))
print('  private repos  :', d.get('total_private_repos'))
PY

echo
echo "== token scopes =="
curl -s -I -H "Authorization: token $TOK" https://api.github.com/user |
    grep -i '^x-oauth-scopes\|^x-accepted-oauth-scopes' | sed 's/^/  /'

echo
echo "== rate limit =="
code=$(api https://api.github.com/rate_limit)
python3 -c "import json;d=json.load(open('/tmp/gh_body'));c=d['resources']['core'];print('  core:',c['remaining'],'/',c['limit'])" 2>/dev/null

echo
echo "== does nickdemon22/ios-a51 already exist? =="
code=$(api https://api.github.com/repos/nickdemon22/ios-a51)
echo "  GET /repos/nickdemon22/ios-a51 -> $code"

echo
echo "== can it create repos / run actions? (dry look at the fork source) =="
code=$(api https://api.github.com/repos/Floppikrob/ios-galaxy-s8)
echo "  GET /repos/Floppikrob/ios-galaxy-s8 -> $code"
python3 -c "import json;d=json.load(open('/tmp/gh_body'));print('  fork:',d.get('fork'),'| default_branch:',d.get('default_branch'),'| pushed_at:',d.get('pushed_at'))" 2>/dev/null
