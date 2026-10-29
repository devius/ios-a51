#!/bin/bash
# Install a mac-metal-ios.sh build on the phone over SSH and check every file's hash.
#   tools/a51/host/metal-install.sh BUILDDIR      (e.g. ../build/metal8)
# lib/*.dylib -> /private/var/a51gpu/lib, everything else -> /private/var/a51gpu/metal.
set -euo pipefail
b=${1:?usage: $0 BUILDDIR}
repo=$(cd "$(dirname "$0")/../../.." && pwd)
keys=$(cd "$repo/../build/ssh" && pwd)
ssh_=(ssh -i "$keys/a51_ed25519" -o "UserKnownHostsFile=$keys/known_hosts" -o BatchMode=yes -o ConnectTimeout=10 root@192.168.7.2)
"${ssh_[@]}" 'mkdir -p /private/var/a51gpu/metal /private/var/a51gpu/lib && chmod 755 /private/var/a51gpu/metal'
n=0
while read -r sum f <&3; do
	case "$f" in lib/*) dst=/private/var/a51gpu/$f; mode=644 ;; *.metallib) dst=/private/var/a51gpu/metal/$f; mode=644 ;; *) dst=/private/var/a51gpu/metal/$f; mode=755 ;; esac
	timeout 120 "${ssh_[@]}" "cat > $dst.new && chmod $mode $dst.new && mv $dst.new $dst" < "$b/$f"
	got=$(timeout 30 "${ssh_[@]}" "/var/jb/usr/bin/sha256sum $dst" < /dev/null | cut -d' ' -f1)
	[ "$got" = "$sum" ] || { echo "hash mismatch: $f"; exit 1; }
	n=$((n + 1))
done 3< "$b/SHA256SUMS"
echo "installed $n files from $b, hashes match"
