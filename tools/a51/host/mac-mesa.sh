#!/bin/bash
# Build gpu/mesa (Mesa Panfrost in OSMesa for the A51's iOS) on the Mac VM.
#   tools/a51/host/mac-mesa.sh OUTDIR     (e.g. ../build/mesa1)
# Copies gpu/mesa to the VM (ssh devi@localhost -p 50922, key
# build/ssh/mac_ed25519), runs build-mesa.sh there with the venv and tools
# from setup-mac-build.sh, and fetches lib/*.dylib, osmesa-test, SHA256SUMS
# and build.log into OUTDIR. Mesa and libdrm are cloned on the VM once and
# kept in ~/a51build/mesa-work; delete that to start clean.
set -euo pipefail
out=${1:?usage: $0 OUTDIR}
repo=$(cd "$(dirname "$0")/../../.." && pwd)
keys=$(cd "$repo/../build/ssh" && pwd)
ssh_opts=(-p 50922 -i "$keys/mac_ed25519" -o "UserKnownHostsFile=$keys/mac_known_hosts")
scp_opts=(-P 50922 -i "$keys/mac_ed25519" -o "UserKnownHostsFile=$keys/mac_known_hosts" -q)
mac=devi@localhost

ssh "${ssh_opts[@]}" $mac 'rm -rf ~/a51build/mesa-src ~/a51build/mesa-out && mkdir -p ~/a51build/mesa-src'
scp "${scp_opts[@]}" "$repo"/gpu/mesa/* $mac:a51build/mesa-src/
echo "building Mesa on the VM, started $(date +%T)"
set +e
ssh "${ssh_opts[@]}" $mac 'export PATH=$HOME/mesa-venv/bin:/usr/local/bin:$PATH; cd ~/a51build &&
	bash mesa-src/build-mesa.sh ~/a51build/mesa-work ~/a51build/mesa-out > mesa-build.log 2>&1; rc=$?;
	echo "build-mesa.sh exit=$rc at $(date +%T)";
	grep -nE "error:|FAILED:|ERROR:|Undefined symbols|ld: [^w]" mesa-build.log | grep -v warning | tail -30;
	exit $rc'
rc=$?
set -e
mkdir -p "$out"
scp "${scp_opts[@]}" $mac:a51build/mesa-build.log "$out/build.log"
[[ $rc == 0 ]] || { echo "build failed (log: $out/build.log)"; exit $rc; }
scp "${scp_opts[@]}" -r $mac:a51build/mesa-out/lib $mac:a51build/mesa-out/osmesa-test "$out/"
(cd "$out" && sha256sum osmesa-test lib/*.dylib > SHA256SUMS)
echo "fetched into $out:"
ls -l "$out" "$out/lib"
