#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""corpus.py --backend bifrost with fake air2nir and compiler scripts.

  python3 gpu/metal/tools/test_corpus.py
"""
import os, subprocess, sys, tempfile, unittest

HERE = os.path.dirname(os.path.abspath(__file__))
CORPUS = os.path.join(HERE, 'corpus.py')

# air2nir --report LIB: one line per function, all translated
AIR2NIR = '''#!/bin/sh
printf 'module=fn_ok\\tcontainer=fragment\\tstage=fragment\\ttranslate=ok\\tnir_instrs=10\\n'
printf 'module=fn_bad\\tcontainer=fragment\\tstage=fragment\\ttranslate=ok\\tnir_instrs=10\\n'
printf 'module=fn_crash\\tcontainer=vertex\\tstage=vertex\\ttranslate=ok\\tnir_instrs=10\\n'
'''
# compiler --gpu-id ID LIB FN
COMPILER = '''#!/bin/sh
case "$4" in
  fn_ok) echo "function=fn_ok stage=fragment bytes=256 constants=0" ;;
  fn_bad) echo "fn_bad: unsupported intrinsic" >&2; exit 1 ;;
  fn_crash) echo "Assertion failed: bi_ra" >&2; kill -ABRT $$ ;;
esac
'''


def script(d, name, text):
    p = os.path.join(d, name)
    open(p, 'w').write(text)
    os.chmod(p, 0o755)
    return p


class BifrostBackend(unittest.TestCase):
    def run_corpus(self):
        d = tempfile.mkdtemp()
        lib = os.path.join(d, 'lib.metallib')
        open(lib, 'wb').write(b'MTLB' + bytes(60))
        r = subprocess.run([sys.executable, CORPUS, '--backend', 'bifrost', '--air2nir', script(d, 'air2nir', AIR2NIR),
                            '--compiler', script(d, 'cc', COMPILER), '--gpu-id', '0x6221', '-j', '1', lib],
                           capture_output=True, text=True, timeout=60)
        return r

    def test_counts_ok_and_fail(self):
        r = self.run_corpus()
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertIn('functions=3', r.stdout)
        self.assertIn('bifrost_ok=1', r.stdout)
        self.assertIn('unsupported intrinsic', r.stdout)

    def test_compiler_crash_is_a_failure(self):
        r = self.run_corpus()
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertIn('signal N: Assertion failed', r.stdout)   # failure classes normalise numbers


if __name__ == '__main__':
    unittest.main()
