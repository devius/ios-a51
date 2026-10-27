#!/usr/bin/env python3
"""Extract one IM4P payload from an IPSW without unpacking the archive.

  im4p_extract.py IPSW MEMBER OUT        e.g. Firmware/all_flash/DeviceTree.d22ap.im4p

IM4P is DER: SEQUENCE { IA5String "IM4P", IA5String type, IA5String
description, OCTET STRING payload, [compression SEQUENCE { 1, size }] }.
Unencrypted payloads only; LZFSE ("bvx2", like the A11 device trees) is
decoded with the lzfse command-line tool (apt install lzfse).
"""
import subprocess
import sys
import zipfile


def der(buf, off):
    tag = buf[off]
    n = buf[off + 1]
    off += 2
    if n & 0x80:
        k = n & 0x7f
        n = int.from_bytes(buf[off:off + k], 'big')
        off += k
    return tag, off, n


ipsw, member, out = sys.argv[1:4]
with zipfile.ZipFile(ipsw) as z:
    blob = z.read(member)
tag, off, _ = der(blob, 0)
assert tag == 0x30, 'not a DER SEQUENCE'
fields = []
while off < len(blob) and len(fields) < 5:
    tag, start, n = der(blob, off)
    fields.append((tag, blob[start:start + n]))
    off = start + n
assert fields[0] == (0x16, b'IM4P'), 'not an IM4P'
kind = fields[1][1].decode()
assert fields[3][0] == 0x04, 'payload is not an OCTET STRING'
payload = fields[3][1]
size = None
if len(fields) > 4:
    tag, body = fields[4]
    if tag != 0x30:
        raise SystemExit(f'{member}: unexpected IM4P field {tag:#x} (encrypted?), not supported')
    _, o, n = der(body, 0)
    algo = int.from_bytes(body[o:o + n], 'big')
    _, o2, n2 = der(body, o + n)
    size = int.from_bytes(body[o2:o2 + n2], 'big')
    if algo != 1:
        raise SystemExit(f'{member}: compression {algo} not supported')
if payload[:4] in (b'bvx2', b'bvx1', b'bvxn', b'bvx-'):
    payload = subprocess.run(['lzfse', '-decode'], input=payload,
                             capture_output=True, check=True).stdout
    if size is not None and len(payload) != size:
        raise SystemExit(f'{member}: decoded {len(payload)} bytes, expected {size}')
open(out, 'wb').write(payload)
print(f'{member}: type {kind}, {len(payload)} bytes -> {out}')
