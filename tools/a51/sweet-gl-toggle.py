#!/usr/bin/env python3
"""Turn the GPU UI (EAGL shim in backboardd) on or off on the A51, over SSH.

  sweet-gl-toggle.py on|off|status [--blit] [--direct]

Edits backboardd's job in the phone's /System/Library/xpc/launchd.plist
(read at boot: reboot afterwards; a reboot writes no partition):
  on   DYLD_INSERT_LIBRARIES=/private/var/a51gpu/lib/libheroeagl.dylib, and the
       shim's GPU paths that start off: BGL_NODIRECT=1, HERO_GPU_BLIT=0
       (--blit sets HERO_GPU_BLIT=1, --direct sets BGL_NODIRECT=0)
  off  backboardd's job as it was (the keys this tool adds are removed)
The kernel lets dyld honour the variable for backboardd's first 2 launches
per boot (patch 0146; boot-arg a51gl=0 turns that off). The first edit keeps
the original plist on the phone as /private/var/a51gpu/launchd.plist.orig.
Writes go to a temp file whose hash is checked before it replaces the plist.
"""
import hashlib
import os
import plistlib
import subprocess
import sys

BB = '/System/Library/LaunchDaemons/com.apple.backboardd.plist'
PLIST = '/System/Library/xpc/launchd.plist'
ORIG = '/private/var/a51gpu/launchd.plist.orig'
SHIM = '/private/var/a51gpu/lib/libheroeagl.dylib'
KEYS = ('DYLD_INSERT_LIBRARIES', 'BGL_NODIRECT', 'HERO_GPU_BLIT')
HERE = os.path.dirname(os.path.abspath(__file__))
KEYDIR = os.path.normpath(os.path.join(HERE, '../../../build/ssh'))
SSH = ['ssh', '-i', f'{KEYDIR}/a51_ed25519', '-o', f'UserKnownHostsFile={KEYDIR}/known_hosts',
       '-o', 'BatchMode=yes', '-o', 'ConnectTimeout=10', 'root@192.168.7.2']


def edit(data, on, blit=False, direct=False):
    """launchd.plist bytes with backboardd's shim environment set (on) or removed."""
    plist = plistlib.loads(data)
    job = plist.get('LaunchDaemons', {}).get(BB)
    if job is None:
        sys.exit(f'no {BB} job in launchd.plist')
    env = dict(job.get('EnvironmentVariables', {}))
    for k in KEYS:
        env.pop(k, None)
    if on:
        env.update({'DYLD_INSERT_LIBRARIES': SHIM,
                    'BGL_NODIRECT': '0' if direct else '1',
                    'HERO_GPU_BLIT': '1' if blit else '0'})
    if env:
        job['EnvironmentVariables'] = env
    else:
        job.pop('EnvironmentVariables', None)
    return plistlib.dumps(plist, fmt=plistlib.FMT_BINARY)


def status(data):
    env = plistlib.loads(data)['LaunchDaemons'][BB].get('EnvironmentVariables', {})
    return {'on': env.get('DYLD_INSERT_LIBRARIES') == SHIM, 'env': {k: env[k] for k in KEYS if k in env}}


def ssh(cmd, stdin=None):
    r = subprocess.run(SSH + [cmd], input=stdin, capture_output=True, timeout=60)
    if r.returncode:
        sys.exit(f'ssh {cmd!r} failed: {r.stderr.decode().strip()}')
    return r.stdout


def main():
    args = sys.argv[1:]
    if not args or args[0] not in ('on', 'off', 'status'):
        sys.exit(__doc__)
    data = ssh(f'cat {PLIST}')
    if args[0] == 'status':
        print(status(data))
        return
    new = edit(data, args[0] == 'on', '--blit' in args, '--direct' in args)
    want = hashlib.sha256(new).hexdigest()
    ssh(f'[ -e {ORIG} ] || cp -p {PLIST} {ORIG}')
    got = ssh(f'cat > {PLIST}.new && shasum -a 256 {PLIST}.new 2>/dev/null || sha256sum {PLIST}.new', new).split()[0].decode()
    if got != want:
        ssh(f'rm -f {PLIST}.new')
        sys.exit(f'upload hash mismatch ({got} != {want}); plist unchanged')
    ssh(f'chown 0:80 {PLIST}.new && chmod 644 {PLIST}.new && mv {PLIST}.new {PLIST} && sync')
    print('now:', status(ssh(f'cat {PLIST}')), '- reboot for launchd to read it')


if __name__ == '__main__':
    main()
