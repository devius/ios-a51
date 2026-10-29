#!/bin/bash
# SPDX-License-Identifier: MIT
# iOS build (in the VM) of air_metal.c over Panfrost: libairmetal.dylib and the
# phone tests, on top of the Mesa tree gpu/mesa/build-mesa.sh built.
#   gpu/metal/build-ios.sh MESA_WORK OUT
# MESA_WORK is build-mesa.sh's work dir (its mesa/ is patched and built for iOS;
# build-mesa.sh resets it at its next run, so this adds its parts each time).
# OUT gets lib/libairmetal.dylib, a51_device_test, bgair_test and the metallibs.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
WORK="${1:?usage: $0 MESA_WORK OUT}"; OUT="${2:?}"
MIN_IOS=16.0
SDK=$(xcrun --sdk iphoneos --show-sdk-path)
CC_IOS="xcrun --sdk iphoneos clang -arch arm64 -miphoneos-version-min=$MIN_IOS -isysroot $SDK"
M="$WORK/mesa"

git -C "$M" apply --check "$HERE/patches/air-frontend.patch" 2>/dev/null && git -C "$M" apply "$HERE/patches/air-frontend.patch"
mkdir -p "$M/src/compiler/air"
for f in "$HERE"/air/*; do ln -sf "$f" "$M/src/compiler/air/$(basename "$f")"; done
ln -sf "$HERE/a51/sweet_drm_hero.c" "$M/src/gallium/targets/osmesa/sweet_drm_hero.c"
ln -sf "$HERE/../mesa/hero_hw.c" "$M/src/gallium/targets/osmesa/hero_hw_metal.c"
MB="$M/src/gallium/targets/osmesa/meson.build"
# this script's stanza is the file's tail from its marker on: replaced every run
if grep -q '^# ios-a51 gpu/metal/build-ios.sh' "$MB"; then
  sed -i '' '/^# ios-a51 gpu\/metal\/build-ios.sh/,$d' "$MB"
fi
{
  cat <<'EOM'
# ios-a51 gpu/metal/build-ios.sh: Chlorophyll's air_metal.c over Panfrost (HeroGPU)
libairmetal = shared_library('airmetal',
  meson.project_source_root() / 'src/compiler/air/air_metal.c', 'hero_hw_metal.c', 'sweet_drm_hero.c',
  include_directories : [inc_include, inc_src, inc_gallium, inc_gallium_aux, inc_gallium_winsys,
                         inc_gallium_drivers, include_directories('../../winsys/sw')],
  link_with : [libgallium, libws_null],
  dependencies : [driver_panfrost, driver_swrast, idep_air, idep_nir, idep_mesautil, dep_libdrm,
                  idep_xmlconfig, dep_thread],
  install : false)
EOM
} >> "$MB"
ninja -C "$M/build" src/gallium/targets/osmesa/libairmetal.dylib

mkdir -p "$OUT/lib"
cp "$M/build/src/gallium/targets/osmesa/libairmetal.dylib" "$OUT/lib/"
install_name_tool -id @rpath/libairmetal.dylib "$OUT/lib/libairmetal.dylib"
for dep in $(otool -L "$OUT/lib/libairmetal.dylib" | awk 'NR > 1 { print $1 }'); do
  case "$dep" in /usr/lib/*|/System/*|@rpath/*) ;; *) install_name_tool -change "$dep" "@rpath/$(basename "$dep")" "$OUT/lib/libairmetal.dylib" ;; esac
done
DRM="$WORK/drm-standin/libdrm.2.dylib"
for t in "$HERE/test/a51/a51_device_test.c" "$HERE/test/a51/a51_surface_test.c" "$HERE/test/bgair_test.c" "$HERE/test/bgair_vertex_test.c" "$HERE/test/a51/a51_render_diag.c"; do
  $CC_IOS -O2 -Wall -I "$HERE/air" -o "$OUT/$(basename "$t" .c)" "$t" -L "$OUT/lib" -lairmetal "$DRM" -framework IOSurface -framework CoreFoundation \
    -Wl,-rpath,/private/var/a51gpu/lib
done
xcrun -sdk iphoneos metal -std=ios-metal2.4 -target air64-apple-ios16.0 "$HERE/test/a51/a51_kernels.metal" -o "$OUT/a51_kernels.metallib"
xcrun -sdk iphoneos metal -std=ios-metal2.4 -target air64-apple-ios16.0 "$HERE/test/bg_kernels.metal" -o "$OUT/bg_kernels.metallib"
xcrun -sdk iphoneos metal -std=ios-metal2.4 -target air64-apple-ios16.0 "$HERE/test/bg_render.metal" -o "$OUT/bg_render.metallib"
for f in "$OUT/lib/libairmetal.dylib" "$OUT/a51_device_test" "$OUT/a51_surface_test" "$OUT/bgair_test" "$OUT/bgair_vertex_test" "$OUT/a51_render_diag"; do codesign -s - -f "$f"; done
otool -L "$OUT/lib/libairmetal.dylib"
