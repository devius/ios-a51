#!/usr/bin/env python3
"""Round-trip check for a generated ADT: parse it back and print the nodes the
A51 port depends on (chosen DRAM, arm-io GIC, fbcon, ufs, cpu list)."""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import adt


def find(node, name):
    for c in node.children:
        if c.name == name:
            return c
        hit = find(c, name)
        if hit is not None:
            return hit
    return None


def show(node, label):
    if node is None:
        print(f'{label}: MISSING')
        return
    print(f'{label} ({node.name}):')
    for key, _flags, value in node.props:
        print(f'    {key} = {adt.fmt(value, hexall=True)}')


def main():
    blob = Path(sys.argv[1]).read_bytes()
    root, _ = adt.parse(blob)
    print(f'parsed {len(blob)} bytes; root children: {len(root.children)}')
    show(root, 'root.compatible')
    chosen = find(root, 'chosen')
    if chosen is not None:
        for key in ('dram-base', 'dram-size'):
            value = chosen.prop(key)
            print(f'chosen.{key} = {hex(value) if isinstance(value, int) else value}')
    arm_io = find(root, 'arm-io')
    if arm_io is not None:
        print(f'arm-io device_type={arm_io.prop("device_type")}')
        show(find(arm_io, 'gic'), 'arm-io/gic')
        show(find(arm_io, 'disp0'), 'arm-io/disp0')
    show(find(root, 'a5xelte-fbcon'), 'fbcon')
    show(find(root, 'a51-ufs'), 'ufs')
    cpus = find(root, 'cpus')
    if cpus is not None:
        for c in cpus.children:
            print(f'  {c.name}: reg={c.prop("reg")} state={c.prop("state")!r} '
                  f'cluster={c.prop("cluster-id")}')


if __name__ == '__main__':
    main()
