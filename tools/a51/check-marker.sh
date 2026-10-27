#!/bin/bash
T=/home/nickolay/xnuwork/xnu
REPO=/mnt/g/a51-port/ios-a51
echo "== A5_ENTRY_MARKER_PHYS in the board header (A51 vs DREAMLTE) =="
grep -n -B4 -A4 'ENTRY_MARKER' "$T/pexpert/pexpert/arm64/A5XELTE.h"
echo
echo "== marker references in the xnu tree =="
grep -rn 'A5_ENTRY_MARKER\|ENTRY_MARKER' "$T" --include=*.c --include=*.h --include=*.s --include=*.cpp | sed "s#$T/##"
echo
echo "== does the shim read it back? =="
grep -rn 'MARKER\|marker' "$REPO/shim/a51"/*.c "$REPO/shim/a51"/*.h | head -20
echo
echo "== framebuffer/text markers in start.s (A5XELTE block) =="
grep -n 'La5_text_entry\|A5_FB\|La5_draw_text' "$T/osfmk/arm64/start.s" | head -20
