#!/bin/bash
# Build the kernel on the Mac VM instead of GitHub CI, from this checkout.
#   tools/a51/host/mac-kernel.sh OUTDIR     (e.g. ../build/kernel140)
# Copies xnu/patches, the workflow (for DXB_SHA) and mac-build-xnu.sh to the
# VM (ssh devi@localhost -p 50922, key build/ssh/mac_ed25519), runs the build
# there and fetches OUTDIR/kernel.development.a5xelte, SHA256SUMS, build.log.
# Interactive (-t), so the first build can ask for sudo to install the KDK.
set -euo pipefail
out=${1:?usage: $0 OUTDIR}
repo=$(cd "$(dirname "$0")/../../.." && pwd)
keys=$(cd "$repo/../build/ssh" && pwd)
ssh_opts=(-p 50922 -i "$keys/mac_ed25519" -o "UserKnownHostsFile=$keys/mac_known_hosts")
scp_opts=(-P 50922 -i "$keys/mac_ed25519" -o "UserKnownHostsFile=$keys/mac_known_hosts" -q)
mac=devi@localhost

ssh "${ssh_opts[@]}" $mac 'rm -rf ~/a51build/src && mkdir -p ~/a51build/src/patches'
scp "${scp_opts[@]}" "$repo"/xnu/patches/*.patch "$repo"/xnu/patches/*.sh $mac:a51build/src/patches/
scp "${scp_opts[@]}" "$repo/.github/workflows/xnu.yml" "$repo/tools/a51/host/mac-build-xnu.sh" $mac:a51build/src/
echo "patches: $(ls "$repo"/xnu/patches/*.patch | wc -l), last $(basename "$(ls "$repo"/xnu/patches/*.patch | tail -1)")"
ssh -t "${ssh_opts[@]}" $mac 'bash ~/a51build/src/mac-build-xnu.sh ~/a51build/src'
mkdir -p "$out"
scp "${scp_opts[@]}" $mac:a51build/out/kernel.development.a5xelte $mac:a51build/out/SHA256SUMS $mac:a51build/out/build.log "$out/"
echo "fetched into $out:"
ls -l "$out"
