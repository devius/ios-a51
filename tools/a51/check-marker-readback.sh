#!/bin/bash
REPO=/mnt/g/a51-port/ios-a51
for f in "$REPO"/backup/logs/pstore-boot10/pmsg-ramoops-0 \
         "$REPO"/backup/logs/pstore-boot9/pmsg-ramoops-0; do
  echo "== $f =="
  grep -c 'XNUELTE1' "$f" 2>/dev/null || echo "  marker absent"
  echo "  first 64 bytes:"
  head -c 64 "$f" | od -A d -t x1z | sed 's/^/    /'
  echo "  bytes at offset 12..20 (A5_ENTRY_MARKER_PHYS is zone+0xc):"
  dd if="$f" bs=1 skip=12 count=8 2>/dev/null | od -A d -t x1z | sed 's/^/    /'
done
echo
echo "== does pmsg contain any XNU-ish text? =="
for f in "$REPO"/backup/logs/pstore-boot10/pmsg-ramoops-0; do
  grep -a -o -E 'Darwin|XNU|xnu|panic|fault|Exception|start_first|A51' "$f" | sort | uniq -c
done
