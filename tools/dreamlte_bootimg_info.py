#!/usr/bin/env python3
"""Print and unpack a Samsung (Exynos) Android boot.img v0 with a 'dt' section.

Samsung reuses the header_version slot (offset 0x28) as dt_size; the DT blob
follows the second-stage area. Usage: bootimg_info.py boot.img [outdir]
"""
import os
import struct
import sys

img = open(sys.argv[1], 'rb').read()
assert img[:8] == b'ANDROID!', 'not an Android boot image'
(ksz, kaddr, rsz, raddr, ssz, saddr, tags, page, dtsz, osver) = struct.unpack_from('<10I', img, 8)
name = img[0x30:0x40].split(b'\0')[0]
cmdline = img[0x40:0x240].split(b'\0')[0]
print(f'kernel  size={ksz:#x} addr={kaddr:#x}')
print(f'ramdisk size={rsz:#x} addr={raddr:#x}')
print(f'second  size={ssz:#x} addr={saddr:#x}')
print(f'tags={tags:#x} pagesize={page} dt_size={dtsz:#x} os_version={osver:#x}')
print(f'name={name!r}')
print(f'cmdline={cmdline!r}')

def pages(n):
    return (n + page - 1) // page * page

off = page
parts = {}
for key, sz in (('kernel', ksz), ('ramdisk', rsz), ('second', ssz), ('dt', dtsz)):
    parts[key] = img[off:off + sz]
    off += pages(sz)
tail = img[off:].rstrip(b'\0')
print(f'payload ends at {off:#x}; trailing non-zero bytes: {len(tail)} start={tail[:16]!r}')
k = parts['kernel']
print(f'kernel magic: {k[:4].hex()} arm64-hdr={k[0x38:0x3c]!r} text_offset={struct.unpack_from("<Q", k, 8)[0]:#x}' if len(k) > 0x40 else '')
print(f'dt head: {parts["dt"][:16]!r}')
if len(sys.argv) > 2:
    os.makedirs(sys.argv[2], exist_ok=True)
    for key, data in parts.items():
        open(os.path.join(sys.argv[2], key), 'wb').write(data)
    open(os.path.join(sys.argv[2], 'header'), 'wb').write(img[:page])
