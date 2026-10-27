#!/bin/bash
# Commit the current tree, create the public ios-a51 repo, push main and report
# the workflow run that the push triggers. The token is never printed.
set -uo pipefail
REPO=/mnt/g/a51-port/ios-a51
TOK=$(tr -d '\r\n' < /mnt/g/a51-port/toolchain/gh_token.txt)
OWNER=nickdemon22
NAME=ios-a51
CLEAN_URL="https://github.com/$OWNER/$NAME.git"

api() { curl -s -o /tmp/gh_body -w '%{http_code}' -H "Authorization: Bearer $TOK" \
        -H 'Accept: application/vnd.github+json' -H 'X-GitHub-Api-Version: 2022-11-28' "$@"; }

cd "$REPO" || exit 1
git config user.name "$OWNER"
git config user.email "$OWNER@users.noreply.github.com"
git config core.fileMode false
git add -A

git commit -q -F - <<'MSG'
a51: extend the board layer to the DREAMLTE guards the A51 needs

0125 now does three things instead of one:

1. Board block in A5XELTE.h with the measured A51 values: framebuffer
   0xca000000 1080x2400 stride 4320 (confirmed by dpp@0x14881000
   IN_BASE_ADDR_Y and by the panel showing the shim paint), DECON_F
   0x148b0000, boot MPIDR 0, 26 MHz physical timer (INTID 30), kernel log in
   the ramoops PMSG zone 0xf9e90000, keys and touch off until Phase 5.

2. UFS identity: ADT node /a51-ufs and lower-case "userdata" (the A51 GPT
   names are lower case; the S8's were not).

3. Guard extension. 0124 wrapped its new code in #if defined(DREAMLTE); the
   board-neutral parts are now (defined(DREAMLTE) || defined(A51)):
   the ramoops console copy in pe_serial.c (the only readable kernel log on
   this device - it has no /dev/mem and no /proc/kcore), the framebuffer VA
   reservation and the deterministic physmap in arm_vm_init.c, and the CPU_ON
   trampoline for a high-bank entry in SweetCPU.cpp. SweetFramebuffer.cpp gets
   the frame-done wait with a parameterised A5_DECON_PHYS instead of the S8's
   hard-coded 0x12860000.
   Deliberately left S8-only: the MPIDR topology (A51 measured A53 = 0x0-0x3
   as the boot cluster, which is the existing A5XELTE branch), the iPhone-X
   logical display size, the S6SY761 touch driver and the S8 key sampling.

Verified on a real xnu-8796.141.3 tree: 0125 applies with plain git apply, and
tools/a51/verify-board-routes.sh shows the patch route and the apply-a51.py
route produce identical trees.
MSG
echo "HEAD: $(git rev-parse --short HEAD)  files: $(git ls-files | wc -l)"

echo
echo "== create the public repo =="
code=$(api -X POST https://api.github.com/user/repos -d \
  "{\"name\":\"$NAME\",\"private\":false,\"has_issues\":true,\"has_wiki\":false,\"auto_init\":false,\"description\":\"iOS 16 XNU port for Samsung Galaxy A51 (SM-A515F, Exynos 9611)\"}")
echo "POST /user/repos -> $code"
head -c 300 /tmp/gh_body; echo

echo
echo "== push main =="
git remote remove origin 2>/dev/null
git remote add origin "https://$OWNER:$TOK@github.com/$OWNER/$NAME.git"
git push -u origin main 2>&1 | sed -E "s#$TOK#<token>#g" | tail -6
git remote set-url origin "$CLEAN_URL"
echo "remote: $(git remote get-url origin)"

echo
sleep 8
echo "== workflow runs =="
code=$(api "https://api.github.com/repos/$OWNER/$NAME/actions/runs?per_page=5")
echo "GET /actions/runs -> $code"
python3 - <<'PY'
import json
d = json.load(open('/tmp/gh_body'))
runs = d.get('workflow_runs', [])
if not runs:
    print('  no runs yet')
for r in runs:
    print(f"  {r['id']} {r['name']} {r['status']}/{r.get('conclusion')} "
          f"branch={r['head_branch']} {r['html_url']}")
PY
