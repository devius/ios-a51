#!/usr/bin/env python3
"""Remove launchd jobs from the A51's iOS (read at boot), over SSH; or restore.

  sweet-launchd-disable.py LABEL [LABEL ...]     remove these jobs
  sweet-launchd-disable.py --restore              put the saved original back

For daemons that crash in a loop because their hardware is missing, and the
crash reporter that then works through every crash (boot 46: ReportCrash at
216% CPU, locationd and WirelessRadioManagerd respawning with KeepAlive),
as tools/sweet-root-tweaks.py removes CommCenter from the image. The first run
keeps the original as /private/var/a51gpu/launchd.plist.pre-disable; writes go
to a temp file whose hash is checked before it replaces the plist. Reboot
afterwards.
"""
import hashlib
import plistlib
import sys

sys.path.insert(0, __import__('os').path.dirname(__file__))
toggle = __import__('importlib.util').util
spec = toggle.spec_from_file_location('t', __import__('os').path.join(__import__('os').path.dirname(__file__), 'sweet-gl-toggle.py'))
t = toggle.module_from_spec(spec)
spec.loader.exec_module(t)

PLIST = '/System/Library/xpc/launchd.plist'
SAVED = '/private/var/a51gpu/launchd.plist.pre-disable'


def remove(data, labels):
    plist = plistlib.loads(data)
    jobs = plist['LaunchDaemons']
    gone = [k for k, v in jobs.items() if v.get('Label') in labels]
    missing = set(labels) - {jobs[k].get('Label') for k in gone}
    if missing:
        sys.exit('no such jobs: ' + ', '.join(sorted(missing)))
    for k in gone:
        del jobs[k]
    return plistlib.dumps(plist, fmt=plistlib.FMT_BINARY), gone


def put(new):
    want = hashlib.sha256(new).hexdigest()
    got = t.ssh(f'cat > {PLIST}.new && (shasum -a 256 {PLIST}.new 2>/dev/null || sha256sum {PLIST}.new)', new).split()[0].decode()
    if got != want:
        t.ssh(f'rm -f {PLIST}.new')
        sys.exit(f'upload hash mismatch; plist unchanged')
    t.ssh(f'chown 0:80 {PLIST}.new && chmod 644 {PLIST}.new && mv {PLIST}.new {PLIST} && sync')


def main():
    args = sys.argv[1:]
    if not args:
        sys.exit(__doc__)
    if args == ['--restore']:
        put(t.ssh(f'cat {SAVED}'))
        print('restored the original launchd.plist - reboot')
        return
    data = t.ssh(f'cat {PLIST}')
    new, gone = remove(data, args)
    t.ssh(f'mkdir -p /private/var/a51gpu && ([ -e {SAVED} ] || cp -p {PLIST} {SAVED})')
    put(new)
    print('removed:', ', '.join(gone), '- reboot for launchd to read it')


if __name__ == '__main__':
    main()
