#!/usr/bin/env python3
"""Debug helper: what does the post-0124 reconstruction of a file look like?"""
import sys
from pathlib import Path
HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import mkpatch0125 as M

rel = sys.argv[1]
needle = sys.argv[2] if len(sys.argv) > 2 else 'DREAMLTE'
text = M.DREAMLTE_PATCH.read_text()

print(f'== hunk headers for {rel} in 0124 ==')
lines = text.splitlines()
i = 0
while i < len(lines):
    if lines[i].startswith('diff --git') and lines[i].endswith(f'{rel} {rel}'):
        break
    i += 1
i += 1
while i < len(lines) and not lines[i].startswith('diff --git'):
    if lines[i].startswith('@@'):
        print('  ' + lines[i])
    i += 1

img = M.post_image(text, rel)
print(f'\n== reconstruction: {len(img)} lines '
      f'({img[0][0]}..{img[-1][0]}) ==') if img else print('EMPTY')
print(f'== lines containing {needle!r} ==')
for n, t in img:
    if needle in t:
        print(f'  {n}: {t}')
