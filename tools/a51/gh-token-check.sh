#!/bin/bash
# Validate the GitHub token stored in /mnt/g/a51-port/toolchain/gh_token.txt.
# The token value is never printed.
set -uo pipefail
TOKFILE=/mnt/g/a51-port/toolchain/gh_token.txt
TOK=$(tr -d '\r\n' < "$TOKFILE")
echo "token length: ${#TOK}, prefix: ${TOK:0:11}..."

api() { curl -s -o /tmp/gh_body -w '%{http_code}' -H "Authorization: Bearer $TOK" \
        -H 'Accept: application/vnd.github+json' -H 'X-GitHub-Api-Version: 2022-11-28' "$@"; }

echo "GET /user -> $(api https://api.github.com/user)"
python3 - <<'PY'
import json
try:
    d = json.load(open('/tmp/gh_body'))
except Exception as e:
    print('  body:', open('/tmp/gh_body').read()[:300]); raise SystemExit
print('  login        :', d.get('login'))
print('  id           :', d.get('id'))
plan = d.get('plan') or {}
print('  plan         :', plan.get('name'))
print('  public repos :', d.get('public_repos'))
print('  private repos:', d.get('total_private_repos'))
PY

echo
echo "== scopes / permissions =="
curl -s -D - -o /dev/null -H "Authorization: Bearer $TOK" https://api.github.com/user |
  grep -i '^x-oauth-scopes\|^x-accepted-oauth-scopes\|^x-github-api-version' | sed 's/^/  /'

echo
echo "== can it see the donor repos? =="
for r in Floppikrob/ios-galaxy-s8 dipa-studio/ios-sweet nickdemon22/ztOS-a51 nickdemon22/ios-a51; do
  echo "  $r -> $(api https://api.github.com/repos/$r)"
done

echo
echo "== actions permission on the account =="
echo "  /user/actions/permissions -> $(api https://api.github.com/user/actions/permissions)"
cat /tmp/gh_body | head -c 300; echo
