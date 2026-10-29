# gpu/metal on the Galaxy A51

Chlorophyll (https://github.com/ry-diffusion/Chlorophyll, MIT, see
`LICENSE.hackios-userland` and `NOTICE.md`), vendored at commit
`787338fc7c297f54e2000bca02f4fa36f1154c5a` (`UPSTREAM`), for Metal on the
Mali-G72 through Mesa Panfrost (design:
`docs/superpowers/specs/2026-10-29-a51-gpu-metal-design.md`).

Left out: the `mesa/` and `libdrm/` submodules (we build our own Mesa 25.0.7,
`gpu/mesa/`), `results/` (Adreno measurements), the eight freedreno/ir3 Mesa
patches (`air-ir3`, `ir3-*`, `fd*`), `build-host.sh`, `build-ios.sh`,
`build-probe.sh` (Bergamota/Adreno builds; ours replace them).

`check-vendor.sh` checks every file below against upstream.

## Changed files

- tools/corpus.py
- air/air_metal.c (Panfrost device over HeroGPU, GPU faults reported, IOSurfaces imported as descriptors, freedreno-only parts guarded)

## Added files

- check-vendor.sh
- build-host.sh
- host/air_bifrost.c
- test/host/test_air_bifrost.sh
- test/host/fixtures/quad.metal
- test/host/fixtures/quad.metallib
- tools/test_corpus.py
- results/ios16.7-bifrost.md
- build-ios.sh
- a51/sweet_drm_hero.c
- test/a51/a51_device_test.c
- test/a51/a51_kernels.metal
- test/a51/a51_surface_test.c
