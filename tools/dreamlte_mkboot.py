#!/usr/bin/env python3
"""Build a Samsung (Exynos) boot.img v0 that reuses the stock header and DT.

Takes addresses, page size, os_version, name and the DTBH 'dt' section from
the stock boot.img; replaces kernel and ramdisk. Appends SEANDROIDENFORCE
like the stock image.
Usage: mkboot_samsung.py stock_boot.img Image ramdisk out.img
"""
import hashlib
import struct
import sys

stock = open(sys.argv[1], 'rb').read()
kernel = open(sys.argv[2], 'rb').read()
ramdisk = open(sys.argv[3], 'rb').read()
assert stock[:8] == b'ANDROID!'
(ksz, kaddr, rsz, raddr, ssz, saddr, tags, page, dtsz, osver) = struct.unpack_from('<10I', stock, 8)


def pages(n):
    return (n + page - 1) // page * page


off = page + pages(ksz) + pages(rsz) + pages(ssz)
dt = stock[off:off + dtsz]
assert dt[:4] == b'DTBH', 'stock dt section not found'

sha = hashlib.sha1()
for blob in (kernel, ramdisk, b'', dt):
    sha.update(blob)
    sha.update(struct.pack('<I', len(blob)))
digest = sha.digest() + b'\0' * 12

hdr = bytearray(stock[:page])
struct.pack_into('<10I', hdr, 8, len(kernel), kaddr, len(ramdisk), raddr, 0, saddr, tags, page, len(dt), osver)
hdr[0x40:0x240] = b'\0' * 0x200          # empty cmdline, as stock
hdr[0x240:0x260] = digest
hdr[0x260:0x660] = b'\0' * 0x400          # no extra cmdline

out = bytearray(hdr)
for blob in (kernel, ramdisk, dt):
    out += blob + b'\0' * (pages(len(blob)) - len(blob))
out += b'SEANDROIDENFORCE'
open(sys.argv[4], 'wb').write(out)
print(f'{sys.argv[4]}: {len(out)} bytes (kernel {len(kernel)}, ramdisk {len(ramdisk)}, dt {len(dt)})')
