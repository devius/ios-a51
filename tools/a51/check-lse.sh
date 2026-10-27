#!/bin/bash
K=/mnt/g/a51-port/ios-a51/out/kernel.development.a5xelte
echo "== all load commands =="
python3 - "$K" <<'PY'
import struct, sys
b = open(sys.argv[1],'rb').read()
ncmds, = struct.unpack_from('<I', b, 16)
off = 32
for _ in range(ncmds):
    cmd, size = struct.unpack_from('<II', b, off)
    if cmd == 0x19:
        name = b[off+8:off+24].split(b'\0')[0].decode()
        print(f'  {cmd:#x} LC_SEGMENT_64 {name} (size {size})')
    else:
        print(f'  {cmd:#x} size {size}')
    off += size
PY
echo
echo "== LSE mnemonics in the disassembly =="
llvm-objdump -d --no-show-raw-insn "$K" > /tmp/k.dis 2>/dev/null || { echo "objdump failed"; exit 1; }
wc -l /tmp/k.dis
grep -nE '^\s*[0-9a-f]+:\s+(cas|casa|casal|casl|casp|ldadd|ldclr|ldeor|ldset|ldsmax|ldsmin|ldumax|ldumin|stadd|stclr|steor|stset|stsmax|stsmin|stumax|stumin|swp)[a-z]*\s' /tmp/k.dis
echo
echo "== context around each hit =="
for n in $(grep -nE '^\s*[0-9a-f]+:\s+(cas|casa|casal|casl|casp|ldadd|ldclr|ldeor|ldset|ldsmax|ldsmin|ldumax|ldumin|stadd|stclr|steor|stset|stsmax|stsmin|stumax|stumin|swp)[a-z]*\s' /tmp/k.dis | cut -d: -f1); do
  echo "--- hit at line $n"
  sed -n "$((n-12)),$((n+6))p" /tmp/k.dis
done
echo
echo "== nearest preceding symbol for the hits =="
for n in $(grep -nE '^\s*[0-9a-f]+:\s+(cas|casa|casal|casl|casp|ldadd|ldclr|ldeor|ldset|ldsmax|ldsmin|ldumax|ldumin|stadd|stclr|steor|stset|stsmax|stsmin|stumax|stumin|swp)[a-z]*\s' /tmp/k.dis | cut -d: -f1); do
  awk -v n="$n" 'NR<=n && /^[0-9a-f]+ </{sym=$0} NR==n{print n": "sym; exit}' /tmp/k.dis
done
