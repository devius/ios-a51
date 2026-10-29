#!/bin/bash
# SPDX-License-Identifier: MIT
# Host build (macOS, the VM) of air_bifrost: Chlorophyll's AIR frontend + Panfrost's
# Bifrost compiler, for gpu/metal/tools/corpus.py --backend bifrost.
#   gpu/metal/build-host.sh WORK MESA_CHECKOUT LIBDRM_CHECKOUT
# MESA_CHECKOUT is our iOS Mesa tree (~/a51build/mesa-work/mesa): it is cloned with
# `git clone --shared`, so only its 25.0.7 commit is used, never its edits or builds.
# gpu/mesa/patch-mesa.py makes Panfrost build on Darwin; libdrm is headers only
# (the tool talks to no GPU; Panfrost's ioctl calls stay unresolved, dynamic_lookup).
# Produces WORK/build/src/gallium/drivers/panfrost/air_bifrost.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
WORK="${1:?usage: $0 WORK MESA_CHECKOUT LIBDRM_CHECKOUT}"; MESA="${2:?}"; LIBDRM="${3:?}"
mkdir -p "$WORK/pc"
cd "$WORK"
if [ ! -d mesa ]; then
  git clone -q --shared "$MESA" mesa
  (cd mesa && python3 "$HERE/../mesa/patch-mesa.py" .)
  git -C mesa apply "$HERE/patches/air-frontend.patch"
  mkdir -p mesa/src/compiler/air
  cat >> mesa/src/gallium/drivers/panfrost/meson.build <<'EOM'

# ios-a51 gpu/metal/build-host.sh: AIR -> NIR -> Bifrost on the host
executable('air_bifrost', 'air_bifrost.c',
  include_directories : [panfrost_includes, inc_src, inc_include],
  c_args : [compile_args_panfrost],
  link_args : ['-Wl,-undefined,dynamic_lookup'],
  dependencies : [driver_panfrost, idep_air, idep_nir, idep_mesautil, idep_pan_packers, dep_libdrm],
  build_by_default : false)
EOM
fi
for f in "$HERE"/air/*; do ln -sf "$f" "mesa/src/compiler/air/$(basename "$f")"; done
ln -sf "$HERE/host/air_bifrost.c" mesa/src/gallium/drivers/panfrost/air_bifrost.c
cat > pc/libdrm.pc <<EOP
Name: libdrm
Description: headers only
Version: 2.4.124
Cflags: -I$LIBDRM/include/drm -I$LIBDRM
Libs:
EOP
[ -d build ] || PKG_CONFIG_PATH="$WORK/pc" meson setup build mesa --buildtype=debugoptimized -Dplatforms= \
  -Dgallium-drivers=panfrost -Dvulkan-drivers= -Dglx=disabled -Degl=disabled -Dgbm=disabled -Dllvm=disabled \
  -Dopengl=true -Dgles2=enabled -Dshader-cache=disabled -Dvalgrind=disabled -Dlibunwind=disabled -Dglvnd=disabled \
  -Dvideo-codecs= -Dtools= -Dlmsensors=disabled -Dbuild-tests=false -Dzstd=disabled -Dxmlconfig=disabled \
  -Dexpat=disabled -Dgallium-xa=disabled -Dosmesa=false -Dperfetto=false > setup.log
ninja -j"${JOBS:-4}" -C build src/gallium/drivers/panfrost/air_bifrost
echo "air_bifrost: $WORK/build/src/gallium/drivers/panfrost/air_bifrost"
