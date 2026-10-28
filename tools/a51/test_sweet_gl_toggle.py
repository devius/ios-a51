#!/usr/bin/env python3
"""Tests for sweet-gl-toggle.py's plist edit (no phone needed).

  python3 tools/a51/test_sweet_gl_toggle.py [LAUNCHD_PLIST]

LAUNCHD_PLIST: a copy of the phone's /System/Library/xpc/launchd.plist; without
one, a minimal plist with a backboardd job is used.
"""
import importlib.util
import os
import plistlib
import sys
import unittest

here = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location('toggle', os.path.join(here, 'sweet-gl-toggle.py'))
toggle = importlib.util.module_from_spec(spec)
spec.loader.exec_module(toggle)

BB = '/System/Library/LaunchDaemons/com.apple.backboardd.plist'
SAMPLE = None


def sample():
    if SAMPLE:
        return open(SAMPLE, 'rb').read()
    return plistlib.dumps({'LaunchDaemons': {
        BB: {'Label': 'com.apple.backboardd', 'ProgramArguments': ['/usr/libexec/backboardd'],
             'UserName': 'mobile'},
        '/x/other.plist': {'Label': 'other', 'EnvironmentVariables': {'A': '1'}},
    }}, fmt=plistlib.FMT_BINARY)


class Toggle(unittest.TestCase):
    def test_on_sets_shim_env_on_backboardd_only(self):
        before = plistlib.loads(sample())
        after = plistlib.loads(toggle.edit(sample(), True))
        env = after['LaunchDaemons'][BB]['EnvironmentVariables']
        self.assertEqual(env['DYLD_INSERT_LIBRARIES'], '/private/var/a51gpu/lib/libheroeagl.dylib')
        self.assertEqual(env['BGL_NODIRECT'], '1')
        self.assertEqual(env['HERO_GPU_BLIT'], '0')
        for k, job in before['LaunchDaemons'].items():
            if k != BB:
                self.assertEqual(after['LaunchDaemons'][k], job)

    def test_off_restores_the_original_job(self):
        before = plistlib.loads(sample())
        back = plistlib.loads(toggle.edit(toggle.edit(sample(), True), False))
        self.assertEqual(back, before)

    def test_on_twice_is_on_once(self):
        once = toggle.edit(sample(), True)
        self.assertEqual(plistlib.loads(toggle.edit(once, True)), plistlib.loads(once))

    def test_output_is_binary_plist(self):
        self.assertTrue(toggle.edit(sample(), True).startswith(b'bplist00'))

    def test_status(self):
        self.assertFalse(toggle.status(sample())['on'])
        self.assertTrue(toggle.status(toggle.edit(sample(), True))['on'])

    def test_no_backboardd_job_is_an_error(self):
        empty = plistlib.dumps({'LaunchDaemons': {}}, fmt=plistlib.FMT_BINARY)
        with self.assertRaises(SystemExit):
            toggle.edit(empty, True)


if __name__ == '__main__':
    if len(sys.argv) > 1:
        SAMPLE = sys.argv.pop(1)
    unittest.main(verbosity=1)
