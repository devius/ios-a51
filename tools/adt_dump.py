#!/usr/bin/env python3
"""Print an ADT as an indented tree (small values decoded): adt_dump.py FILE"""
import struct
import sys

import adt


def show(value):
    if len(value) in (4, 8, 16, 32) and not value.rstrip(b'\0').isascii():
        n = len(value) // (8 if len(value) >= 8 and len(value) % 8 == 0 else 4)
        fmt = '<%d%s' % (n, 'Q' if len(value) // n == 8 else 'I')
        return ' '.join(hex(v) for v in struct.unpack(fmt, value))
    text = value.rstrip(b'\0')
    if text.isascii() and all(32 <= c < 127 or c == 0 for c in text):
        return repr(text.replace(b'\0', b'|').decode())
    return f'<{len(value)} bytes>'


def walk(node, depth=0):
    name = node.prop('name').rstrip(b'\0').decode()
    print('  ' * depth + '/' + name)
    for key, _, value in node.props:
        if key != 'name':
            print('  ' * depth + f'    {key} = {show(value)}')
    for c in node.children:
        walk(c, depth + 1)


root, _ = adt.parse(open(sys.argv[1], 'rb').read())
walk(root)
