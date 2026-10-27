#!/usr/bin/env python3
"""Generate xnu/patches/0125-a51-exynos9611.patch.

The A51 layer sits on top of 0124-dreamlte-s8.patch, which turned every
hard-coded A5XELTE constant into an A5_* macro, added the Exynos UFS quirks and
wrapped its new code in `#if defined(DREAMLTE)`. 0125 flips the board selector,
adds the A51 board block, and extends exactly the DREAMLTE guards that are
board-neutral (see a51_board.GUARD_SITES for the per-site reasoning).

There is no xnu checkout needed to *generate* this: the post-0124 text is
reconstructed from 0124's own hunks (a hunk's post-image is its context plus
its added lines, and the hunk header gives absolute line numbers), the board
transform is applied to that reconstruction, and difflib turns the difference
back into hunks. tools/a51/verify-patch0125.py then checks the result, and
tools/a51/verify-board-routes.sh checks it against a real tree.

    python tools/a51/mkpatch0125.py [--stdout]
"""
import difflib
import re
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import a51_board as B

ROOT = HERE.parent.parent
DREAMLTE_PATCH = ROOT / 'xnu' / 'patches' / '0124-dreamlte-s8.patch'
OUT = ROOT / 'xnu' / 'patches' / '0125-a51-exynos9611.patch'
CONTEXT = 3


def post_image(patch_text, rel):
    """Reconstruct [(absolute line number, text)] for rel after 0124 applies."""
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
            want = int(m.group(2)) if m.group(2) is not None else 1
            got = 0
            i += 1
            while i < len(lines) and got < want:
                l = lines[i]
                if l.startswith('@@') or l.startswith('diff --git'):
                    break
                if l.startswith('+'):
                    out.append((n, l[1:]))
                    n += 1
                    got += 1
                elif l.startswith(' '):
                    out.append((n, l[1:]))
                    n += 1
                    got += 1
                elif l == '':
                    # A context line that is empty is often written without its
                    # leading space; treat it as context, not as the end of the
                    # hunk, or everything after it is silently lost.
                    out.append((n, ''))
                    n += 1
                    got += 1
                elif l.startswith('-') or l.startswith('\\'):
                    pass
                else:
                    break
                i += 1
            continue
        i += 1
    return out


def transformed(rel, src_lines):
    text = '\n'.join(src_lines)
    if rel == B.HEADER_REL:
        return B.transformed_header(text).split('\n')
    if rel == B.UFS_REL:
        return B.transformed_ufs(text).split('\n')
    return B.transform_lines(rel, src_lines)


def hunks_for(rel, image):
    src = [t for _, t in image]
    dst = transformed(rel, src)
    if src == dst:
        return []
    sm = difflib.SequenceMatcher(a=src, b=dst, autojunk=False)
    groups = []
    for tag, i1, i2, j1, j2 in sm.get_opcodes():
        if tag == 'equal':
            continue
        if groups and i1 - groups[-1][1] <= 2 * CONTEXT:
            groups[-1] = (groups[-1][0], i2, groups[-1][2], j2)
        else:
            groups.append((i1, i2, j1, j2))

    out = []
    for i1, i2, j1, j2 in groups:
        start = max(0, i1 - CONTEXT)
        end = min(len(src), i2 + CONTEXT)
        dstart = max(0, j1 - (i1 - start))
        dend = min(len(dst), j2 + (end - i2))
        # Context must exist on both sides and be contiguous in the real file.
        head = src[start:i1]
        tail = src[i2:end]
        if head != dst[dstart:dstart + len(head)] or tail != dst[dend - len(tail):dend]:
            raise SystemExit(f'{rel}: context mismatch around line {image[i1][0]}')
        for k in range(start, end - 1):
            if image[k + 1][0] != image[k][0] + 1:
                raise SystemExit(
                    f'{rel}: reconstruction is not contiguous at line '
                    f'{image[k][0]}->{image[k + 1][0]}; cannot build a hunk')
        body = ([' ' + l for l in head] +
                ['-' + l for l in src[i1:i2]] +
                ['+' + l for l in dst[j1:j2]] +
                [' ' + l for l in tail])
        old_start = image[start][0]
        old_count = len(head) + (i2 - i1) + len(tail)
        new_count = len(head) + (j2 - j1) + len(tail)
        out.append((rel, f'@@ -{old_start},{old_count} +{old_start},{new_count} @@',
                    body))
    return out


HEADER_TEXT = """Galaxy A51 (SM-A515F, Exynos 9611) board layer, on top of 0124.

Flips the board selector from DREAMLTE to A51, adds the measured A51 board
block, and extends the DREAMLTE guards that are board-neutral so the A51 gets
the ramoops console copy (pexpert/arm/pe_serial.c), the framebuffer VA
reservation and deterministic physmap (osfmk/arm64/arm_vm_init.c), the CPU_ON
trampoline for a high-bank entry (iokit/Kernel/arm/SweetCPU.cpp) and the
frame-done wait before each copy (iokit/Kernel/arm/SweetFramebuffer.cpp, with
the A51 DECON base).

Deliberately NOT extended: the S8 MPIDR topology (A51 measured A53 = MPIDR
0x0-0x3 as the boot cluster, which is the existing A5XELTE branch), the S8
logical display size (A51 presents its native 1080x2400), the S6SY761 touch
driver (A51 has a Melfas MMS100) and the S8 key sampling (A51 ALIVE pinctrl is
0x11850000 with the keys on banks 5/6/7 pin 15; A5_KEYS_DEFAULT is 0 until that
is written).

All values measured on hardware by shim/a51; see A51_PROGRESS.md for the boot
log and the evidence for each one: framebuffer 0xca000000 1080x2400 stride 4320
(dpp@0x14881000 IN_BASE_ADDR_Y), DECON_F 0x148b0000 in command mode, GICD
0x12301000 / GICC 0x12302000 disabled at handoff, 26 MHz physical timer (INTID
30), UFSHCI 2.1 at 0x13520000 with userdata at LBA 0x1f7500, and the log channel
is the ramoops pmsg zone 0xf9e90000 -> /sys/fs/pstore/pmsg-ramoops-0.
"""


def main():
    patch_text = DREAMLTE_PATCH.read_text()
    to_stdout = '--stdout' in sys.argv

    all_hunks = []
    for rel in B.EDITED_FILES:
        image = post_image(patch_text, rel)
        if not image:
            raise SystemExit(f'{rel}: could not reconstruct from 0124')
        all_hunks.extend(hunks_for(rel, image))

    out = [HEADER_TEXT]
    for rel, hdr, body in all_hunks:
        out.append(f'diff --git a/{rel} b/{rel}')
        out.append(f'--- a/{rel}')
        out.append(f'+++ b/{rel}')
        out.append(hdr)
        out.extend(body)
    text = '\n'.join(out) + '\n'

    if to_stdout:
        sys.stdout.write(text)
    else:
        # newline='\n': a CRLF patch makes git apply bail out in CI.
        with OUT.open('w', encoding='utf-8', newline='\n') as fh:
            fh.write(text)
        print(f'{OUT.relative_to(ROOT)}: {len(text)} bytes, '
              f'{len(all_hunks)} hunks over {len(set(h[0] for h in all_hunks))} files')
        for rel, hdr, body in all_hunks:
            print(f'  {rel}: {hdr}')


if __name__ == '__main__':
    main()
