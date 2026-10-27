#!/usr/bin/env python3
"""Generate xnu/patches/0125-a51-exynos9611.patch.

The A51 layer sits on top of 0124-dreamlte-s8.patch, which already turned every
hard-coded A5XELTE constant into an A5_* macro and proved the Exynos UFS quirks
on the S8. 0125 only has to re-point the board selector and the two board facts
that are not macros yet (the UFS ADT node name and the GPT partition case).

There is no xnu checkout on this host, so the post-0124 text is reconstructed
from 0124's own hunks: a hunk's post-image is its context plus its added lines,
and the hunk header gives the absolute line numbers. Context for the new hunks
is taken from that reconstruction, so the result applies to a tree that has been
patched to 0124.

    python tools/a51/mkpatch0125.py            # writes the patch
    python tools/a51/mkpatch0125.py --stdout
"""
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import a51_board as B

ROOT = Path(__file__).resolve().parents[2]
DREAMLTE_PATCH = ROOT / 'xnu' / 'patches' / '0124-dreamlte-s8.patch'
OUT = ROOT / 'xnu' / 'patches' / '0125-a51-exynos9611.patch'
CONTEXT = 3


def post_image(patch_text, rel):
    """Reconstruct (absolute line number, text) for every post-0124 line of rel."""
    lines = patch_text.splitlines()
    i = 0
    while i < len(lines):
        if lines[i].startswith('diff --git') and lines[i].endswith(f'{rel} {rel}'):
            break
        i += 1
    if i == len(lines):
        raise SystemExit(f'{rel}: no diff in {DREAMLTE_PATCH.name}')
    i += 1
    out = []
    while i < len(lines) and not lines[i].startswith('diff --git'):
        line = lines[i]
        m = re.match(r'^@@ -\d+(?:,\d+)? \+(\d+)(?:,(\d+))? @@', line)
        if m:
            n = int(m.group(1))
            i += 1
            while i < len(lines):
                l = lines[i]
                if l.startswith('@@') or l.startswith('diff --git'):
                    break
                if l.startswith('+'):
                    out.append((n, l[1:]))
                    n += 1
                elif l.startswith(' '):
                    out.append((n, l[1:]))
                    n += 1
                elif l.startswith('-'):
                    pass
                elif l.startswith('\\'):
                    pass
                else:
                    break
                i += 1
            continue
        i += 1
    return out


def find_line(image, text):
    hits = [k for k, (n, t) in enumerate(image) if t == text]
    if len(hits) != 1:
        raise SystemExit(f'expected 1x {text!r} in the reconstructed file, found {len(hits)}')
    return hits[0]


def hunk(image, changes, header):
    """changes: list of (index, [removed lines], [added lines])."""
    first = min(c[0] for c in changes)
    last = max(c[0] for c in changes)
    start = max(0, first - CONTEXT)
    end = min(len(image) - 1, last + CONTEXT)

    idx = set(c[0] for c in changes)
    by_idx = {c[0]: c for c in changes}
    old_start = image[start][0]
    new_start = old_start
    body = []
    for k in range(start, end + 1):
        n, t = image[k]
        if k in idx:
            _removed, added = by_idx[k][1], by_idx[k][2]
            body.append('-' + t)
            for a in added:
                body.append('+' + a)
        else:
            body.append(' ' + t)

    old_count = sum(1 for b in body if b[0] in ' -')
    new_count = sum(1 for b in body if b[0] in ' +')
    return [f'@@ -{old_start},{old_count} +{new_start},{new_count} @@ {header}'] + body


def main():
    patch_text = DREAMLTE_PATCH.read_text()
    to_stdout = '--stdout' in sys.argv

    hdr_image = post_image(patch_text, B.HEADER_REL)
    ufs_image = post_image(patch_text, B.UFS_REL)
    if not hdr_image or not ufs_image:
        raise SystemExit('could not reconstruct the post-0124 files')

    sel = find_line(hdr_image, B.DREAMLTE_SELECTOR)
    guard = find_line(hdr_image, B.DREAMLTE_GUARD)
    if guard != sel + 1:
        raise SystemExit('unexpected A5XELTE.h layout: selector and guard not adjacent')

    hdr_changes = []
    for old, new in B.HEADER_LINE_SUBSTITUTIONS:
        hdr_changes.append((find_line(hdr_image, old), [], [new]))
    hdr_changes.append((guard, [], [B.A51_GUARD] + B.A51_HEADER_BLOCK +
                        [B.A51_ELSE_GUARD]))
    hdr_hunk = hunk(hdr_image, hdr_changes, '')

    ufs_changes = []
    for old, new in B.UFS_SUBSTITUTIONS:
        ufs_changes.append((find_line(ufs_image, old), [], [new]))
    ufs_hunk = hunk(ufs_image, ufs_changes, '')

    out = []
    out.append('Galaxy A51 (SM-A515F, Exynos 9611) board layer, on top of 0124.')
    out.append('')
    out.append('Board facts measured on hardware by shim/a51 and recorded in')
    out.append('A51_PROGRESS.md: framebuffer 0xca000000 1080x2400 stride 4320')
    out.append('(confirmed by dpp@0x14881000 IN_BASE_ADDR_Y and by the panel')
    out.append('showing the shim paint), boot CPU MPIDR 0 (Cortex-A53), GICD')
    out.append('0x12301000 / GICC 0x12302000 disabled at handoff, 26 MHz')
    out.append('physical timer (INTID 30), UFSHCI 2.1 at 0x13520000, and the')
    out.append('log channel is the ramoops dump zone at 0xf9d10000 which recovery')
    out.append('exposes as /sys/fs/pstore/dmesg-ramoops-0.')
    out.append('')
    out.append(f'diff --git a/{B.HEADER_REL} b/{B.HEADER_REL}')
    out.append(f'--- a/{B.HEADER_REL}')
    out.append(f'+++ b/{B.HEADER_REL}')
    out.extend(hdr_hunk)
    out.append(f'diff --git a/{B.UFS_REL} b/{B.UFS_REL}')
    out.append(f'--- a/{B.UFS_REL}')
    out.append(f'+++ b/{B.UFS_REL}')
    out.extend(ufs_hunk)
    text = '\n'.join(out) + '\n'

    if to_stdout:
        sys.stdout.write(text)
    else:
        # newline='\n': a CRLF patch makes git apply bail out in CI.
        with OUT.open('w', encoding='utf-8', newline='\n') as fh:
            fh.write(text)
        print(f'{OUT.relative_to(ROOT)}: {len(text)} bytes')


if __name__ == '__main__':
    main()
