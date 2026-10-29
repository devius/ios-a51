#!/bin/bash
# Build gpu/metal's host tool air_bifrost on the Mac VM and run its test.
#   tools/a51/host/mac-metal-host.sh [corpus.py ARGS...]
# Copies gpu/metal and gpu/mesa to ~/a51build/gpu-src, builds in
# ~/a51build/metal-host (kept; delete it to start clean) from the Mesa and libdrm
# trees mac-mesa.sh left in ~/a51build/mesa-work, then runs
# test/host/test_air_bifrost.sh. With arguments, also runs corpus.py on the VM
# with them (paths are VM paths).
set -euo pipefail
repo=$(cd "$(dirname "$0")/../../.." && pwd)
keys=$(cd "$repo/../build/ssh" && pwd)
ssh_opts=(-p 50922 -i "$keys/mac_ed25519" -o "UserKnownHostsFile=$keys/mac_known_hosts" -o BatchMode=yes)
mac=devi@localhost
bin='~/a51build/metal-host/build/src/gallium/drivers/panfrost/air_bifrost'
ssh "${ssh_opts[@]}" $mac 'rm -rf ~/a51build/gpu-src && mkdir -p ~/a51build/gpu-src'
tar -C "$repo/gpu" -cf - metal mesa | ssh "${ssh_opts[@]}" $mac 'tar -C ~/a51build/gpu-src -xf -'
ssh "${ssh_opts[@]}" $mac "export PATH=\$HOME/mesa-venv/bin:/usr/local/bin:\$PATH; cd ~/a51build &&
	bash gpu-src/metal/build-host.sh ~/a51build/metal-host ~/a51build/mesa-work/mesa ~/a51build/mesa-work/libdrm > metal-host.log 2>&1 ||
	{ grep -E 'error:|FAILED|ERROR' metal-host.log | head -20; exit 1; }
	QC_METALLIB=\$HOME/a51build/ios-metallibs/QuartzCore.metallib bash gpu-src/metal/test/host/test_air_bifrost.sh $bin"
if [ $# -gt 0 ]; then
	ssh "${ssh_opts[@]}" $mac "python3 ~/a51build/gpu-src/metal/tools/corpus.py --backend bifrost --air2nir ~/a51build/metal-host/build/src/compiler/air/air2nir --compiler $bin $(printf '%q ' "$@")"
fi
