#!/bin/bash
# One-shot analysis of the failed build: download the job log into $HOME
# (persistent), then report the real cause.
set -uo pipefail
TOK=$(tr -d '\r\n' < /mnt/g/a51-port/toolchain/gh_token.txt)
OWNER=nickdemon22
NAME=ios-a51
RUN=${1:-40452629749}
LOG=$HOME/a51-job-$RUN.log

if [ ! -s "$LOG" ]; then
  curl -s -H "Authorization: Bearer $TOK" \
    "https://api.github.com/repos/$OWNER/$NAME/actions/runs/$RUN/jobs" -o "$HOME/jobs-$RUN.json"
  jid=$(python3 - "$HOME/jobs-$RUN.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
print(d['jobs'][0]['id'])
PY
)
  echo "job $jid -> $LOG"
  curl -sL -H "Authorization: Bearer $TOK" \
    "https://api.github.com/repos/$OWNER/$NAME/actions/jobs/$jid/logs" -o "$LOG"
fi
echo "log: $LOG ($(wc -l < "$LOG") lines)"

# strip timestamps into a working file
sed -E 's/^[0-9T:.Z-]+ //' "$LOG" > "$HOME/a51-build-$RUN.txt"
B=$HOME/a51-build-$RUN.txt

echo
echo "=== make invocations ==="
grep -n 'TARGET_CONFIGS\|make install \|Building xnu\|building xnu' "$B" | head -10

echo
echo "=== dxb status lines ==="
grep -n '\[info\]\|\[error\]\|\[warning\]\|\[success\]' "$B" | tail -20

echo
echo "=== last 15 lines that are neither -W warnings nor source echoes ==="
grep -vE 'warning:|note:|\^|^ *$|In file included|#define|__auto_type|_os_atomic|^\s+[a-zA-Z_].*;$|generated\.' "$B" |
  tail -15

echo
echo "=== anything mentioning kernel link / install / ctfmarge ==="
grep -niE 'ld: error|Undefined symbols|duplicate symbol|ctfmerge|kextsymboltool|Linking|install .*kernel|No such file' "$B" | tail -20
