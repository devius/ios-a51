#!/usr/bin/env python3
"""Verify xnu/patches/0125-a51-exynos9611.patch without needing an xnu checkout.

Checks, for every hunk:
  1. the header counts match the body,
  2. every context and removed line exists verbatim at the stated line number in
     the post-0124 reconstruction,
  3. applying the hunk to that reconstruction reproduces exactly what
     a51_board.transformed_file() produces -- so the patch route and the
     apply-a51.py route cannot drift.

    python tools/a51/verify-patch0125.py
"""
import re
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import a51_board as B
import mkpatch0125 as M

ROOT = HERE.parent.parent
patch = (ROOT / 'xnu' / 'patches' / '0125-a51-exynos9611.patch').read_text().splitlines()
dreamlte = M.DREAMLTE_PATCH.read_text()

# ---- parse the patch into (rel, old_start, body) ---------------------------
hunks = []
rel = None
i = 0
while i < len(patch):
    line = patch[i]
    if line.startswith('--- a/'):
        rel = line[6:]
    m = re.match(r'^@@ -(\d+),(\d+) \+(\d+),(\d+) @@', line)
    if m:
        body = []
        i += 1
        while i < len(patch) and patch[i][:1] in (' ', '-', '+'):
            body.append(patch[i])
            i += 1
        hunks.append((rel, int(m.group(1)), int(m.group(2)), int(m.group(4)), body))
        continue
    i += 1

if not hunks:
    raise SystemExit('no hunks parsed from the patch')

problems = []
by_file = {}
for rel, start, old_count, new_count, body in hunks:
    by_file.setdefault(rel, []).append((start, old_count, new_count, body))

for rel, start, old_count, new_count, body in hunks:
    old = sum(1 for b in body if b[0] in ' -')
    new = sum(1 for b in body if b[0] in ' +')
    if old != old_count:
        problems.append(f'{rel}: header says {old_count} old lines, body has {old}')
    if new != new_count:
        problems.append(f'{rel}: header says {new_count} new lines, body has {new}')

# ---- check context against the post-0124 reconstruction -------------------
images = {}
for rel in by_file:
    images[rel] = dict(M.post_image(dreamlte, rel))
    if not images[rel]:
        problems.append(f'{rel}: could not reconstruct from 0124')

for rel, start, old_count, new_count, body in hunks:
    image = images[rel]
    n = start
    for b in body:
        kind, text = b[0], b[1:]
        if kind == '+':
            continue
        if image.get(n) != text:
            problems.append(f'{rel}:{n}: {kind!r} line mismatch '
                            f'{image.get(n)!r} != {text!r}')
        n += 1

# ---- apply the patch to the reconstruction and compare with the transform --
for rel, hs in by_file.items():
    image = M.post_image(dreamlte, rel)
    lines = [t for _, t in image]
    nums = [n for n, _ in image]
    # Descending order: applying a later hunk first keeps earlier line numbers
    # valid while the list length changes.
    for start, old_count, new_count, body in sorted(hs, key=lambda h: -h[0]):
        lead = 0
        while lead < len(body) and body[lead][0] == ' ':
            lead += 1
        trail = 0
        while trail < len(body) and body[len(body) - 1 - trail][0] == ' ':
            trail += 1
        if start not in nums:
            problems.append(f'{rel}: hunk start {start} not in the reconstruction')
            continue
        at = nums.index(start) + lead
        removed = [b[1:] for b in body if b[0] == '-']
        added = [b[1:] for b in body if b[0] == '+']
        if lines[at:at + len(removed)] != removed:
            problems.append(f'{rel}:{start}: removed lines do not match the '
                            f'reconstructed file')
            continue
        if trail:
            after = lines[at + len(removed):at + len(removed) + trail]
            want_after = [b[1:] for b in body[len(body) - trail:]]
            if after != want_after:
                problems.append(f'{rel}:{start}: trailing context does not match')
        lines[at:at + len(removed)] = added
    want = B.transformed_file(rel, '\n'.join([t for _, t in image]))
    if '\n'.join(lines) != want:
        problems.append(f'{rel}: patched result differs from a51_board transform')

# ---- every file the board layer touches must appear in the patch -----------
for rel in B.EDITED_FILES:
    if rel not in by_file:
        problems.append(f'{rel}: edited by a51_board but absent from the patch')

if problems:
    print('FAILED')
    for p in problems:
        print('  ' + p)
    raise SystemExit(1)

print(f'0125-a51-exynos9611.patch verified: {len(hunks)} hunks over {len(by_file)} files')
for rel, hs in by_file.items():
    for start, old_count, new_count, body in hs:
        print(f'  {rel}: @@ -{start},{old_count} +{start},{new_count} @@ '
              f'({len(body)} body lines)')
print('  context matches post-0124; result equals tools/a51/a51_board.py transform')
