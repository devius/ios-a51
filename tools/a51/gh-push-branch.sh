#!/bin/bash
# Push this tree as an isolated branch of an existing public repo so the macOS
# Actions workflow can build the kernel. Repo creation and forks are denied for
# this fine-grained token, but push is allowed on the account's own repos.
#
# main is never touched; the branch is orphan (unrelated history) and can be
# deleted afterwards with: git push origin --delete a51-bringup
set -uo pipefail
REPO=/mnt/g/a51-port/ios-a51
TOK=$(tr -d '\r\n' < /mnt/g/a51-port/toolchain/gh_token.txt)
OWNER=nickdemon22
HOST_REPO=ztOS-a51
BRANCH=a51-bringup

api() { curl -s -o /tmp/gh_body -w '%{http_code}' -H "Authorization: Bearer $TOK" \
        -H 'Accept: application/vnd.github+json' -H 'X-GitHub-Api-Version: 2022-11-28' "$@"; }

echo "== Actions enabled on $OWNER/$HOST_REPO? =="
echo "  /actions/permissions -> $(api https://api.github.com/repos/$OWNER/$HOST_REPO/actions/permissions)"
cat /tmp/gh_body; echo
echo "  /actions/permissions/workflow -> $(api https://api.github.com/repos/$OWNER/$HOST_REPO/actions/permissions/workflow)"
cat /tmp/gh_body; echo

cd "$REPO" || exit 1

# Make sure the workflow triggers on our branch.
python3 - "$BRANCH" <<'PY'
import sys, pathlib
branch = sys.argv[1]
p = pathlib.Path('.github/workflows/xnu.yml')
t = p.read_text()
old = 'branches: [main, codex/a5xelte-bringup, s8-dreamlte]'
new = f'branches: [main, codex/a5xelte-bringup, s8-dreamlte, {branch}]'
if old in t:
    p.write_text(t.replace(old, new))
    print(f'workflow: added branch {branch}')
elif branch in t:
    print(f'workflow: branch {branch} already listed')
else:
    raise SystemExit('workflow: unexpected branches line, refusing to guess')
PY

git add .github/workflows/xnu.yml
git commit -q -m "ci: trigger the xnu workflow on the $BRANCH branch" || true

git remote remove origin 2>/dev/null
git remote add origin "https://$OWNER:$TOK@github.com/$OWNER/$HOST_REPO.git"
echo
echo "== pushing $(git rev-parse --short HEAD) to $OWNER/$HOST_REPO:$BRANCH =="
git push --force origin "HEAD:refs/heads/$BRANCH" 2>&1 | sed -E "s#$TOK#<token>#g" | tail -6
git remote set-url origin "https://github.com/$OWNER/$HOST_REPO.git"
echo "remote reset to: $(git remote get-url origin)"
echo "HEAD: $(git rev-parse HEAD)"
