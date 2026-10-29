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

## Added files

- check-vendor.sh
