#!/bin/bash
# Initialise the local git repo, create the public GitHub repo, and push.
# The token is read from /mnt/g/a51-port/toolchain/gh_token.txt and is scrubbed
# out of .git/config again as soon as the push succeeds.
set -uo pipefail
REPO=/mnt/g/a51-port/ios-a51
TOK=$(tr -d '\r\n' < /mnt/g/a51-port/toolchain/gh_token.txt)
OWNER=nickdemon22
NAME=ios-a51
CLEAN_URL="https://github.com/$OWNER/$NAME.git"

api() { curl -s -o /tmp/gh_body -w '%{http_code}' -H "Authorization: Bearer $TOK" \
        -H 'Accept: application/vnd.github+json' -H 'X-GitHub-Api-Version: 2022-11-28' "$@"; }

cd "$REPO" || exit 1

echo "== what would be published =="
git init -q -b main 2>/dev/null || git init -q
git config user.name "$OWNER"
git config user.email "$OWNER@users.noreply.github.com"
git config core.fileMode false
git config core.autocrlf false
git add -A
echo "staged files: $(git diff --cached --name-only | wc -l)"
echo "staged bytes: $(git diff --cached --name-only | xargs -r du -ch 2>/dev/null | tail -1)"
echo "-- ignored directories that must NOT appear --"
git status --porcelain --ignored | awk '$1=="!!"{print "  ignored: "$2}' | head
echo "-- any backup/research/ipsw/serial leaked into the index? --"
git diff --cached --name-only | grep -E '^backup/|^research/|\.ipsw$|\.img$|\.dtb$' | head
git diff --cached --name-only | wc -l | xargs echo "  index file count:"
git grep --cached -lE 'RZ8[A-Z0-9]{8}|ghp_[A-Za-z0-9]{20}|github_pat_' -- . 2>/dev/null | head
echo "  (nothing above = clean)"

git commit -q -m "A51 (SM-A515F, Exynos 9611) bring-up: shim, board layer, patch 0125

Boot 1 verified on hardware: S-Boot hands off at EL1/MMU off on MPIDR 0,
framebuffer 0xca000000 1080x2400 is scanned out by dpp@0x14881000, DECON_F is
in command mode and needs no reprogramming, GICD 0x12301000 reads 0xfcef with
the distributor off, UFSHCI 2.1 at 0x13520000 wakes with START STOP UNIT to
WLUN 0xd0 and the GPT reads back (userdata at LBA 0x1f7500).

Evidence channel: the shim forges a persistent_ram record in the ramoops dump
zone (0xf9d10000) which recovery exposes as /sys/fs/pstore/dmesg-ramoops-0;
this recovery has neither /dev/mem nor /proc/kcore, and the sec_* log regions
do not survive. The kernel console ring goes to the pmsg zone (0xf9e90000).

Adds tools/a51 (mkboot.js, apply-a51.py, mkpatch0125.py, verify-patch0125.py,
fdtdump.py, phase1-dump2.ps1, flash-test1.ps1, pull-log.ps1), shim/a51,
tools/mkadt_a51.py and xnu/patches/0125-a51-exynos9611.patch." || true

echo
echo "== create the GitHub repo =="
code=$(api -X POST https://api.github.com/user/repos \
  -d "{\"name\":\"$NAME\",\"private\":false,\"has_issues\":true,\"has_wiki\":false,\"description\":\"iOS 16 XNU port for Samsung Galaxy A51 (SM-A515F, Exynos 9611)\"}")
echo "POST /user/repos -> $code"
head -c 400 /tmp/gh_body; echo

echo
echo "== push =="
git remote remove origin 2>/dev/null
git remote add origin "https://$OWNER:$TOK@github.com/$OWNER/$NAME.git"
git push -u origin main 2>&1 | sed -E "s#$TOK#<token>#g" | tail -5
git remote set-url origin "$CLEAN_URL"
echo "remote is now: $(git remote get-url origin)"
echo "HEAD: $(git rev-parse HEAD)"
