#!/usr/bin/env python3
"""Add an SSH server (OpenSSH) and a shell to an iOS root made by tools/mkiosroot.sh.

  sudo sweet-root-ssh.py MOUNTED_ROOT JB_TREE AUTHORIZED_KEY.pub HOSTKEY_DIR

JB_TREE holds var/jb/... made by tools/procursus-tree.py from Procursus iOS 16
(dists/1900, iphoneos-arm64) packages: openssh-server, bash, coreutils and
their dependencies. Their binaries are ad-hoc signed and load their libraries
from /var/jb, which the SWEET AMFI policy accepts like any signed root binary.
HOSTKEY_DIR holds ssh_host_{ed25519,ecdsa,rsa}_key(.pub), made on the PC with
ssh-keygen, so the host key does not change between reinstalls.

  /private/var/jb          the tree, root-owned; host keys in etc/ssh
  launchd.plist            job com.sweet.sshd: sshd -D on port 22, no PAM, no
                           StrictModes (the real path of ~root/.ssh runs
                           through /private, made on Linux; a key login was
                           refused with them), log in /var/jb/var/log/sshd.log
                           (/dev/console does not reach the UDP log); the
                           earlier com.sweet.dropbear job is removed
                           (Procursus' dropbear needs libtomcrypt1, which
                           the 1900 index lacks)
                           job com.sweet.sshdiag: once the USB link is up,
                           sends SSHDIAG lines to the PC's live log (udp/5140
                           on 192.168.7.1, bash's /dev/udp): root's account
                           as getpwnam sees it, sshd -T, sshd.log, then runs
                           sshd -d on port 2222 (debug: says why a login is
                           refused). Keys as qemu-t8030's bash job
                           (POSIXSpawnType Interactive, no pressured exit);
                           com.sweet.sshlog (no spawn type) never started
  passwd                   "sshd" (uid 75, as iOS's _sshd): sshd's privilege
                           separation user
  root                     shell /var/jb/bin/bash, listed in /etc/shells;
                           AUTHORIZED_KEY in ~root/.ssh
  /bin/sh, /bin/bash       links to /var/jb/bin/bash: iOS has no /bin/sh,
                           which is root's stock shell (sshd refuses users
                           whose shell does not exist) and what system(3)
                           runs

Run as root. Idempotent: /private/var/jb is replaced on every run. The phone
is reached over the USB Ethernet gadget (sweetusb=2) at 192.168.7.2.
"""
import os, plistlib, shutil, sys

LAUNCHD = 'System/Library/xpc/launchd.plist'
JOB = '/System/Library/LaunchDaemons/com.sweet.sshd.plist'
OLD_JOB = '/System/Library/LaunchDaemons/com.sweet.dropbear.plist'
LOG_JOB = '/System/Library/LaunchDaemons/com.sweet.sshlog.plist'
DIAG_JOB = '/System/Library/LaunchDaemons/com.sweet.sshdiag.plist'
DIAG = '/var/jb/usr/libexec/sweet-sshdiag'
DIAG_SCRIPT = r'''#!/var/jb/usr/bin/bash
# com.sweet.sshdiag: SSH diagnostics to the PC's live log (tools/sweet-root-ssh.py)
export PATH=/var/jb/usr/bin:/var/jb/bin:/var/jb/usr/sbin:/var/jb/sbin:/usr/bin:/bin:/usr/sbin:/sbin
udp=/dev/udp/192.168.7.1/5140
for i in $(seq 120); do echo "SSHDIAG start" 2>/dev/null >$udp && break; sleep 2; done
exec >$udp 2>&1
tag() { while IFS= read -r l; do echo "SSHDIAG $1 $l"; done; }
{ id; id root; who am i; ls -lnd / /bin /bin/sh /private /private/var /private/var/root \
	/private/var/root/.ssh /private/var/root/.ssh/authorized_keys /var/jb/bin/bash \
	/var/jb/var/empty /var/jb/var/log; ls -ln /var/jb/var/log; cat /etc/shells; } 2>&1 | tag sys
grep -E '^(root|sshd|_sshd):' /etc/master.passwd /etc/passwd 2>&1 | tag pw
sshd -T -o UsePAM=no -o StrictModes=no 2>&1 | grep -iE 'permitroot|pubkey|password|authorizedkeys|strict|usepam|usedns|allowusers|denyusers' | tag cfg
cat /var/jb/var/log/sshd.log /var/jb/var/log/sshd.out 2>&1 | tail -n 30 | tag log
while true; do
	sshd -d -D -p 2222 -o UsePAM=no -o StrictModes=no -o LogLevel=DEBUG2 2>&1 | tag dbg
	sleep 2
done
'''
SHELL = '/var/jb/bin/bash'
PRIVSEP = {'master.passwd': 'sshd:*:75:75::0:0:sshd Privilege separation:/var/jb/var/empty:/usr/bin/false',
           'passwd': 'sshd:*:75:75:sshd Privilege separation:/var/jb/var/empty:/usr/bin/false'}


def install_tree(root, tree, hostkeys):
    src = os.path.join(tree, 'var/jb')
    dst = os.path.join(root, 'private/var/jb')
    # all of it comes from JB_TREE: replace it (copytree cannot overwrite symlinks)
    if os.path.lexists(dst):
        shutil.rmtree(dst)
    shutil.copytree(src, dst, symlinks=True)
    ssh = os.path.join(dst, 'etc/ssh')
    for n in os.listdir(hostkeys):
        if n.startswith('ssh_host_'):
            shutil.copy(os.path.join(hostkeys, n), os.path.join(ssh, n))
    for d, dirs, files in os.walk(dst):
        for n in [d] + [os.path.join(d, x) for x in dirs + files]:
            os.lchown(n, 0, 0)
    for n in os.listdir(ssh):
        if n.startswith('ssh_host_') and n.endswith('_key'):
            os.chmod(os.path.join(ssh, n), 0o600)
    os.chmod(os.path.join(dst, 'var/empty'), 0o755)
    os.makedirs(os.path.join(dst, 'var/log'), exist_ok=True)
    diag = os.path.join(root, DIAG.lstrip('/').replace('var/jb', 'private/var/jb', 1))
    with open(diag, 'w') as f:
        f.write(DIAG_SCRIPT)
    os.chown(diag, 0, 0)
    os.chmod(diag, 0o755)
    print('installed', dst)


def launchd(root):
    path = os.path.join(root, LAUNCHD)
    st = os.stat(path)
    with open(path, 'rb') as f:
        plist = plistlib.load(f)
    jobs = plist['LaunchDaemons']
    jobs.pop(OLD_JOB, None)
    jobs[JOB] = {
        'Label': 'com.sweet.sshd',
        'ProgramArguments': ['/var/jb/usr/sbin/sshd', '-D', '-o', 'UsePAM=no', '-o', 'StrictModes=no',
                             '-o', 'LogLevel=VERBOSE', '-E', '/var/jb/var/log/sshd.log'],
        'EnvironmentVariables': {'PATH': '/var/jb/usr/bin:/var/jb/bin:/var/jb/usr/sbin:/var/jb/sbin:/usr/bin:/bin:/usr/sbin:/sbin'},
        'StandardOutPath': '/var/jb/var/log/sshd.out',
        'StandardErrorPath': '/var/jb/var/log/sshd.out',
        'UserName': 'root',
        'RunAtLoad': True,
        'KeepAlive': True,
        'POSIXSpawnType': 'Interactive',
    }
    jobs.pop(LOG_JOB, None)
    jobs[DIAG_JOB] = {
        'Label': 'com.sweet.sshdiag',
        'ProgramArguments': ['/var/jb/usr/bin/bash', DIAG],
        'UserName': 'root',
        'RunAtLoad': True,
        'KeepAlive': True,
        'POSIXSpawnType': 'Interactive',
        'EnablePressuredExit': False,
    }
    with open(path, 'wb') as f:
        plistlib.dump(plist, f, fmt=plistlib.FMT_BINARY)
    os.chown(path, st.st_uid, st.st_gid)
    os.chmod(path, st.st_mode & 0o7777)
    print('launchd.plist: jobs com.sweet.sshd, com.sweet.sshdiag')


def bin_sh(root):
    os.makedirs(os.path.join(root, 'bin'), exist_ok=True)
    for n in ('sh', 'bash'):
        path = os.path.join(root, 'bin', n)
        if not os.path.lexists(path):
            os.symlink(SHELL, path)
            os.lchown(path, 0, 0)
    print('/bin/sh, /bin/bash ->', SHELL)


def accounts(root):
    for name in ('master.passwd', 'passwd'):
        path = os.path.join(root, 'private/etc', name)
        lines = open(path).read().split('\n')
        for i, l in enumerate(lines):
            f = l.split(':')
            if f[0] == 'root' and len(f) > 1:
                f[-1] = SHELL
                lines[i] = ':'.join(f)
        lines = [l for l in lines if not l.startswith('sshd:')]
        while lines and not lines[-1]:
            lines.pop()
        open(path, 'w').write('\n'.join(lines + [PRIVSEP[name]]) + '\n')
    shells = os.path.join(root, 'private/etc/shells')
    have = open(shells).read().split() if os.path.exists(shells) else []
    if SHELL not in have:
        with open(shells, 'a') as f:
            f.write(SHELL + '\n')
    print('root shell', SHELL, '+ privsep user sshd')


def authorized_key(root, key):
    d = os.path.join(root, 'private/var/root/.ssh')
    os.makedirs(d, exist_ok=True)
    os.chown(d, 0, 0)
    os.chmod(d, 0o700)
    path = os.path.join(d, 'authorized_keys')
    keys = open(path).read().split('\n') if os.path.exists(path) else []
    line = open(key).read().strip()
    if line not in keys:
        keys = [k for k in keys if k] + [line]
    open(path, 'w').write('\n'.join(keys) + '\n')
    os.chown(path, 0, 0)
    os.chmod(path, 0o600)
    print('authorized key', line.split()[-1])


def main():
    if len(sys.argv) != 5 or not os.path.isdir(os.path.join(sys.argv[1], 'System/Library/xpc')):
        sys.exit(__doc__)
    root, tree, key, hostkeys = sys.argv[1:]
    install_tree(root, tree, hostkeys)
    launchd(root)
    accounts(root)
    bin_sh(root)
    authorized_key(root, key)


if __name__ == '__main__':
    main()
