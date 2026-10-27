#!/bin/bash
# Commit the working tree and push it to nickdemon22/ios-a51 main, which
# triggers the xnu workflow. The token is never printed.
#
#   gh-push-main.sh [COMMIT_MESSAGE_FILE]
#
# With no argument the A51-battery message below is used. Every push to main
# with xnu/patches/** or .github/workflows/xnu.yml changes starts a run.
set -uo pipefail
REPO=/mnt/g/a51-port/ios-a51
TOK=$(tr -d '\r\n' < /mnt/g/a51-port/toolchain/gh_token.txt)
OWNER=nickdemon22
NAME=ios-a51
MSG=${1:-}

cd "$REPO" || exit 1
git add -A
if git diff --cached --quiet; then
  echo "nothing to commit"
else
  if [ -n "$MSG" ]; then
    git commit -q -F "$MSG"
  else
    git commit -q -F - <<'BODY'
a51: split the S8 fuel-gauge branch out of SweetBattery for the A51

Run 40454004618 linked and failed on one symbol: _dreamlte_battery_read,
referenced from SweetBattery::poll() in SweetBattery.cpo. MACHINE_CONFIG is
still A5XELTE for the A51, so 0124's #if defined(ARM64_BOARD_CONFIG_A5XELTE)
block in SweetBattery.cpp selects the S8 path, while the definition lives in
bsd/dev/a5xelte_touch.c under #if defined(DREAMLTE).

Extending that DREAMLTE guard would link S8 MAX77865 HSI2C reads into the A51
kernel, so a51_board.A5XELTE_GUARD_SITES now puts an #if defined(A51) branch
ahead of all four S8 sites: no gauge extern (inline SPMI stubs, SWEET_BAT_MAH
4000u), poll() publishes the same unmeasured AC default the S8 path falls back
to, and start() never arms the poll timer (fReal=false, so sweetbattery=1 stays
inert). SweetBattery.cpp also gains <pexpert/arm64/board_config.h>, which is
where A51 is defined; it used to key only off the ARM64_BOARD_CONFIG_* flags.

0125 is regenerated (17 hunks over 8 files), verify-patch0125.py passes, and
both routes are re-proved byte-identical on a fresh xnu-8796.141.3 tree.
BODY
  fi
fi
echo "HEAD: $(git rev-parse --short HEAD)"

git remote remove origin 2>/dev/null
git remote add origin "https://$OWNER:$TOK@github.com/$OWNER/$NAME.git"
git push -u origin main 2>&1 | sed -E "s#$TOK#<token>#g" | tail -3
git remote set-url origin "https://github.com/$OWNER/$NAME.git"

sleep 10
curl -s -H "Authorization: Bearer $TOK" \
  "https://api.github.com/repos/$OWNER/$NAME/actions/runs?per_page=3" -o /tmp/runs.json
python3 - <<'PY'
import json
d = json.load(open('/tmp/runs.json'))
for r in d.get('workflow_runs', []):
    print(f"run {r['id']} {r['status']}/{r['conclusion']} sha={r['head_sha'][:8]} {r['html_url']}")
PY
