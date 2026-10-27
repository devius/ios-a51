#!/usr/bin/env python3
"""Minimal flattened-device-tree reader for the live A51 DTB.

The port needs facts from the *merged* device tree that S-Boot hands the kernel
(base exynos9610.dts plus the dtbo_idx=3 overlay), which the Samsung source tree
cannot give us: the real GIC base, the live framebuffer reservation, and which
touch/GPIO nodes the overlay actually enabled.

    python tools/a51/fdtdump.py backup/live/fdt.dtb
    python tools/a51/fdtdump.py backup/live/fdt.dtb --node /interrupt-controller
"""
import argparse
import struct
import sys
from pathlib import Path

FDT_BEGIN_NODE = 1
FDT_END_NODE = 2
FDT_PROP = 3
FDT_END = 9

FDT_MAGIC = 0xD00DFEED


class Node:
    def __init__(self, name, parent=None):
        self.name = name
        self.parent = parent
        self.props = []      # list of (name, bytes)
        self.children = []

    @property
    def path(self):
        parts = []
        n = self
        while n is not None and n.name:
            parts.append(n.name)
            n = n.parent
        return '/' + '/'.join(reversed(parts))

    def prop(self, name):
        for k, v in self.props:
            if k == name:
                return v
        return None


def parse(buf):
    magic, totalsize, off_dt_struct, off_dt_strings, off_mem_rsvmap, version = struct.unpack_from('>6I', buf, 0)
    if magic != FDT_MAGIC:
        raise SystemExit(f'not an FDT (magic 0x{magic:08x})')
    strings = buf[off_dt_strings:]
    pos = off_dt_struct
    root = Node('')
    stack = [root]

    def string(off):
        end = strings.index(b'\0', off)
        return strings[off:end].decode('latin1')

    mem_rsv = []
    p = off_mem_rsvmap
    while True:
        addr, size = struct.unpack_from('>QQ', buf, p)
        p += 16
        if addr == 0 and size == 0:
            break
        mem_rsv.append((addr, size))

    while pos < len(buf):
        token = struct.unpack_from('>I', buf, pos)[0]
        pos += 4
        if token == FDT_BEGIN_NODE:
            end = buf.index(b'\0', pos)
            name = buf[pos:end].decode('latin1')
            pos = (end + 4) & ~3
            node = Node(name, stack[-1])
            stack[-1].children.append(node)
            stack.append(node)
        elif token == FDT_END_NODE:
            if len(stack) > 1:
                stack.pop()
        elif token == FDT_PROP:
            ln, nameoff = struct.unpack_from('>II', buf, pos)
            pos += 8
            data = buf[pos:pos + ln]
            pos = (pos + ln + 3) & ~3
            stack[-1].props.append((string(nameoff), data))
        elif token == FDT_END:
            break
        else:
            raise SystemExit(f'bad token {token} at {pos - 4}')
    return root, version, totalsize, mem_rsv


def fmt_value(name, data):
    if not data:
        return '<empty>'
    if name in ('compatible', 'model', 'status', 'device_type', 'clock-names',
                'interrupt-names', 'power-domain-names', 'formfactor'):
        parts = [p.decode('latin1', 'replace') for p in data.split(b'\0') if p]
        return ', '.join(f'"{p}"' for p in parts)
    if data.endswith(b'\0') and all(32 <= b < 127 or b == 0 for b in data):
        return '"' + data.rstrip(b'\0').decode('latin1') + '"'
    if len(data) % 4 == 0 and len(data) <= 64:
        cells = struct.unpack('>%dI' % (len(data) // 4), data)
        return '<' + ' '.join(f'0x{c:x}' for c in cells) + '>'
    if len(data) % 8 == 0 and len(data) <= 64:
        cells = struct.unpack('>%dQ' % (len(data) // 8), data)
        return '<' + ' '.join(f'0x{c:x}' for c in cells) + '>'
    return data.hex()


def walk(node, depth=0, want=None, max_depth=None):
    if want is not None and not (want in node.path or node.path in want):
        pass
    print('  ' * depth + node.path.split('/')[-1] + ' {')
    for name, data in node.props:
        print('  ' * (depth + 1) + f'{name} = {fmt_value(name, data)};')
    for child in node.children:
        walk(child, depth + 1, want, max_depth)
    print('  ' * depth + '};')


def find(node, pred, out=None):
    out = out if out is not None else []
    if pred(node):
        out.append(node)
    for c in node.children:
        find(c, pred, out)
    return out


def show(node, title=None):
    print(f'\n=== {title or node.path} ===')
    for name, data in node.props:
        print(f'  {name} = {fmt_value(name, data)}')


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('dtb', type=Path)
    ap.add_argument('--node', help='print one node by path')
    ap.add_argument('--grep', help='print nodes whose path or compatible matches')
    ap.add_argument('--dump', action='store_true', help='full text dump')
    args = ap.parse_args()

    buf = args.dtb.read_bytes()
    root, version, totalsize, mem_rsv = parse(buf)
    print(f'{args.dtb}: {len(buf)} bytes, FDT v{version}, totalsize={totalsize}, '
          f'{len(mem_rsv)} reserved-memory entries')
    for addr, size in mem_rsv:
        print(f'  reserved: 0x{addr:x} size 0x{size:x} ({size / 1024:.0f} KiB)')

    if args.node:
        hits = find(root, lambda n: n.path == args.node or n.path.rstrip('/') == args.node)
        if not hits:
            print(f'no node {args.node}')
        for n in hits:
            show(n)
        return

    if args.grep:
        pat = args.grep.lower()
        hits = find(root, lambda n: pat in n.path.lower() or
                    (n.prop('compatible') is not None and
                     pat in n.prop('compatible').decode('latin1', 'replace').lower()))
        for n in hits:
            show(n)
        print(f'\n{len(hits)} match(es) for {args.grep!r}')
        return

    if args.dump:
        walk(root)
        return

    # Default: the facts the port depends on.
    for title, pred in [
        ('memory', lambda n: n.name.startswith('memory')),
        ('chosen', lambda n: n.name == 'chosen'),
        ('cpus', lambda n: n.name == 'cpus'),
        ('cpu@*', lambda n: n.name.startswith('cpu@')),
        ('timer', lambda n: 'timer' in n.name and n.prop('compatible') is not None),
        ('interrupt-controller / GIC', lambda n: n.prop('compatible') is not None and
            b'gic' in n.prop('compatible')),
        ('decon / dsi / dpp', lambda n: any(k in n.name for k in ('decon', 'dsim', 'dpp'))),
        ('ufs', lambda n: 'ufs' in n.name),
        ('touchscreen', lambda n: n.prop('compatible') is not None and
            b'ts' in n.prop('compatible') and (b'melfas' in n.prop('compatible') or
                                                b'goodix' in n.prop('compatible') or
                                                b'synaptics' in n.prop('compatible'))),
        ('gpio-keys', lambda n: n.prop('compatible') is not None and
            b'gpio-keys' in n.prop('compatible')),
    ]:
        hits = find(root, pred)
        if not hits:
            continue
        print(f'\n######## {title} ########')
        for n in hits[:12]:
            show(n)


if __name__ == '__main__':
    main()
