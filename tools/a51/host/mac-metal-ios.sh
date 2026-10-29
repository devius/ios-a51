#!/bin/bash
# Build gpu/metal for the phone on the Mac VM: libairmetal.dylib (Chlorophyll's
# air_metal.c over Panfrost) and its tests, on the Mesa tree mac-mesa.sh built.
#   tools/a51/host/mac-metal-ios.sh OUTDIR     (e.g. ../build/metal1)
# Needs a mac-mesa.sh build first (~/a51build/mesa-work); fetches lib/,
# the tests, the metallibs, SHA256SUMS and build.log into OUTDIR.
set -euo pipefail
out=${1:?usage: $0 OUTDIR}
repo=$(cd "$(dirname "$0")/../../.." && pwd)
keys=$(cd "$repo/../build/ssh" && pwd)
ssh_opts=(-p 50922 -i "$keys/mac_ed25519" -o "UserKnownHostsFile=$keys/mac_known_hosts" -o BatchMode=yes)
scp_opts=(-P 50922 -i "$keys/mac_ed25519" -o "UserKnownHostsFile=$keys/mac_known_hosts" -q)
mac=devi@localhost
ssh "${ssh_opts[@]}" $mac 'rm -rf ~/a51build/gpu-src ~/a51build/metal-ios-out && mkdir -p ~/a51build/gpu-src'
tar -C "$repo/gpu" -cf - metal mesa | ssh "${ssh_opts[@]}" $mac 'tar -C ~/a51build/gpu-src -xf -'
set +e
ssh "${ssh_opts[@]}" $mac 'export PATH=$HOME/mesa-venv/bin:/usr/local/bin:$PATH; cd ~/a51build &&
	bash gpu-src/metal/build-ios.sh ~/a51build/mesa-work ~/a51build/metal-ios-out > metal-ios.log 2>&1; rc=$?;
	echo "build-ios.sh exit=$rc"; grep -nE "error:|FAILED:|ERROR:|Undefined symbols|ld: [^w]" metal-ios.log | head -30; exit $rc'
rc=$?
set -e
mkdir -p "$out"
scp "${scp_opts[@]}" $mac:a51build/metal-ios.log "$out/build.log"
[[ $rc == 0 ]] || { echo "build failed (log: $out/build.log)"; exit $rc; }
scp "${scp_opts[@]}" -r $mac:'a51build/metal-ios-out/*' "$out/"
(cd "$out" && sha256sum lib/*.dylib a51_device_test a51_surface_test bgair_test *.metallib > SHA256SUMS)
ls -l "$out" "$out/lib"
