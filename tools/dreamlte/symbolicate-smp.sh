#!/bin/bash
# Symbolicate "SMP name tN pc .. lr .. bt .." sampler lines (sweet_sample.c)
# against the iOS dyld shared cache.
#   symbolicate-smp.sh LOG SYSTEMOS.dmg 'backboardd t0,SpringBoard t1,...' [FRAMES]
# The slide is taken from the "SMP name[pid] slide 0x..." header line.
set -euo pipefail
log=$1 dmg=$2 want=$3 frames=${4:-8}
mnt=/root/s8/mnt-sysos
mkdir -p "$mnt"
if ! mountpoint -q "$mnt"; then
	ln -sf "$dmg" /root/s8/sysos.dmg
	apfs-fuse /root/s8/sysos.dmg "$mnt"
fi
cache=$(find "$mnt" -name dyld_shared_cache_arm64 -path '*com.apple.dyld*' | head -1)
[ -n "$cache" ] || { echo "no dyld_shared_cache_arm64 under $mnt" >&2; exit 1; }
IFS=',' read -ra items <<< "$want"
for item in "${items[@]}"; do
	proc=${item% *} th=${item#* }
	slide=$(grep -m1 "^SMP $proc\[[0-9]*\] slide" "$log" | sed 's/.* slide \(0x[0-9a-f]*\).*/\1/')
	line=$(grep -m1 "^SMP $proc $th " "$log" || true)
	[ -n "$line" ] || { echo "== $proc $th: not found"; continue; }
	echo "== $proc $th (slide $slide)"
	addrs=$(echo "$line" | grep -o '0x[0-9a-f]*' | sed -n '1,2p;4,$p' | head -$((frames + 2)))
	for a in $addrs; do
		[ "$a" = 0x0 ] && continue
		printf '  %s ' "$a"
		ipsw dyld a2s "$cache" "$a" --slide "$slide" 2>/dev/null | tail -1 | sed 's/^[[:space:]]*//' || echo '?'
	done
done
