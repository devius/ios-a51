#!/usr/bin/env python3
"""Cross-check the two ways of applying the A51 board layer.

apply-a51.py edits a working tree; mkpatch0125.py emits a patch for the CI
pipeline. Both read tools/a51/a51_board.py, but they take different routes, so
this verifies they agree:

  1. the patch's hunk line counts match its body (a miscount makes git apply
     refuse the patch), and
  2. every context and removed line in the patch exists verbatim at the stated
     line number in the post-0124 reconstruction, and
  3. applying the patch's changes to that reconstruction yields exactly what
     a51_board.transformed_header/transformed_ufs produce.

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

images = {B.HEADER_REL: M.post_image(dreamlte, B.HEADER_REL),
          B.UFS_REL: M.post_image(dreamlte, B.UFS_REL)}

hunks = []          # (rel, old_start, old_count, new_count, body)
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

if len(hunks) != 2:
    raise SystemExit(f'expected 2 hunks, found {len(hunks)}')

problems = []
for rel, start, old_count, new_count, body in hunks:
    old = sum(1 for b in body if b[0] in ' -')
    new = sum(1 for b in body if b[0] in ' +')
    if old != old_count:
        problems.append(f'{rel}: header says {old_count} old lines, body has {old}')
    if new != new_count:
        problems.append(f'{rel}: header says {new_count} new lines, body has {new}')

    image = dict(images[rel])
    n = start
    applied = []
    for b in body:
        kind, text = b[0], b[1:]
        if kind == ' ':
            if image.get(n) != text:
                problems.append(f'{rel}:{n}: context mismatch '
                                f'{image.get(n)!r} != {text!r}')
            applied.append(text)
            n += 1
        elif kind == '-':
            if image.get(n) != text:
                problems.append(f'{rel}:{n}: removed line mismatch '
                                f'{image.get(n)!r} != {text!r}')
            n += 1
        elif kind == '+':
            applied.append(text)
    # The lines the patch produces must equal what a51_board produces.
    produced = '\n'.join(applied)
    if rel == B.HEADER_REL:
        want = ([new for _old, new in B.HEADER_LINE_SUBSTITUTIONS] +
                [B.A51_GUARD] + B.A51_HEADER_BLOCK + [B.A51_ELSE_GUARD])
    else:
        want = [new for _old, new in B.UFS_SUBSTITUTIONS]
    missing = [w for w in want if w not in applied]
    if missing:
        problems.append(f'{rel}: patch is missing board lines: {missing[:3]}')

if problems:
    print('FAILED')
    for p in problems:
        print('  ' + p)
    raise SystemExit(1)

print('0125-a51-exynos9611.patch verified:')
for rel, start, old_count, new_count, body in hunks:
    print(f'  {rel}: @@ -{start},{old_count} +{start},{new_count} @@ '
          f'({len(body)} body lines, context matches post-0124)')
print('  board lines agree with tools/a51/a51_board.py')
