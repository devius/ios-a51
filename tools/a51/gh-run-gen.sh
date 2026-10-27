#!/bin/bash
S=$HOME/buildstep.txt
echo "=== 'error(s) generated' summaries ==="
grep -n 'error[s]* generated' "$S" | tail -20
echo
echo "=== 'fatal' anywhere ==="
grep -n 'fatal' "$S" | tail -10
echo
echo "=== last 400 lines, filtered to drop warning bodies ==="
tail -400 "$S" | grep -vE '^\s+\^|^#define|^__auto_type|^In file included|note: expanded|^ *$|_os_atomic' | tail -40
echo
echo "=== last timestamps in the step ==="
tail -3 $HOME/a51-job-40452629749.log
