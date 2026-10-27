#!/bin/bash
# Work out what this fine-grained token can actually do: read vs write per repo.
# Nothing is created; ls-remote is read-only and the write probe uses the API's
# dry "get a ref" call plus a branch-listing, never a push.
set -uo pipefail
TOK=$(tr -d '\r\n' < /mnt/g/a51-port/toolchain/gh_token.txt)
OWNER=nickdemon22

echo "== token type / expiry =="
curl -s -D - -o /dev/null -H "Authorization: Bearer $TOK" https://api.github.com/user |
  grep -i '^github-authentication-token-expiration\|^x-oauth-scopes\|^www-authenticate' | sed 's/^/  /'

echo
echo "== read access (git ls-remote) =="
for r in ztOS-a51 mine3d TelegramRT; do
  if git ls-remote "https://$OWNER:$TOK@github.com/$OWNER/$r.git" HEAD >/dev/null 2>&1; then
    echo "  $r: READ ok"
  else
    echo "  $r: READ denied"
  fi
done

echo
echo "== write access probe (create-then-delete a throwaway ref via the API) =="
for r in ztOS-a51 mine3d; do
  sha=$(curl -s -H "Authorization: Bearer $TOK" \
        "https://api.github.com/repos/$OWNER/$r/git/ref/heads/main" |
        python3 -c "import json,sys;print(json.load(sys.stdin).get('object',{}).get('sha',''))" 2>/dev/null)
  if [ -z "$sha" ]; then echo "  $r: cannot read main sha"; continue; fi
  code=$(curl -s -o /tmp/ref_body -w '%{http_code}' -X POST \
         -H "Authorization: Bearer $TOK" -H 'Accept: application/vnd.github+json' \
         "https://api.github.com/repos/$OWNER/$r/git/refs" \
         -d "{\"ref\":\"refs/heads/tmp-token-probe-delete-me\",\"sha\":\"$sha\"}")
  echo "  $r: create ref -> $code"
  head -c 160 /tmp/ref_body; echo
  if [ "$code" = "201" ]; then
    curl -s -o /dev/null -X DELETE -H "Authorization: Bearer $TOK" \
      "https://api.github.com/repos/$OWNER/$r/git/refs/heads/tmp-token-probe-delete-me"
    echo "  $r: probe ref deleted again"
  fi
done
