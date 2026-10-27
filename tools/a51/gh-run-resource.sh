#!/bin/bash
S=$HOME/buildstep.txt
echo "=== crash / resource markers ==="
grep -niE 'stack dump|please submit a bug report|assertion failed|segmentation fault|killed|signal [0-9]|no space left|out of memory|panic' "$S" | head -20

echo
echo "=== how many source files were compiled ==="
grep -cE '^/Applications/Xcode.*clang -x c' "$S"
echo "distinct .c targets:"
grep -oE '\-c /Users/.*\.(c|cpp|s|S|m)$' "$S" | sort -u | wc -l
echo "distinct xnu objects:"
grep -oE '\-o /Users/runner/work/ios-a51/ios-a51/dxb/build/xnu.obj/[^ ]+\.o' "$S" | sort -u | wc -l

echo
echo "=== which xnu dirs compiled (top-level, counts) ==="
grep -oE '\-c /Users/runner/work/ios-a51/ios-a51/dxb/xnu/[a-zA-Z0-9_]+/[a-zA-Z0-9_]+' "$S" |
  sed 's|.*/xnu/||' | cut -d/ -f1 | sort | uniq -c | sort -rn | head -15

echo
echo "=== link stage markers ==="
grep -nE '^\s*(LD|LINK|CODESIGN|CTFMERGE|GEN)\b' "$S" | tail -8

echo
echo "=== timestamps of last 5 build lines vs step end ==="
tail -5 "$S"
