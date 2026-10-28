# A51 GPU, sub-project 2: Mesa Panfrost (Bifrost) inside iOS — design

Status: approved by the owner ("go ahead"), 2026-10-29; builder check answered below.

## Intent

Sub-project 1 made the Galaxy A51's Mali-G72 MP3 usable from iOS user space:
the kernel's `HeroGPU` IOKit service (patches 0138–0144) creates GPU buffers,
maps them, and runs job chains; `herogpu-test` ran a `WRITE_VALUE` job from
an iOS process. Sub-project 2 puts a real OpenGL driver on top: Mesa's
Panfrost, which compiles shaders for Bifrost and builds the job chains, so
that later CoreAnimation can draw through it (sub-project 3, EAGL for
backboardd).

**Done when (the owner's words: "triangle with fps is enough"):** a test
program on the phone draws a triangle with OpenGL through Panfrost on the
Mali (not Mesa's software renderer), checks the pixels, and prints frames per
second; the same program with the software renderer gives the comparison.

## Goals

- Mesa (OSMesa + Gallium Panfrost, Bifrost compiler) cross-built for the
  iPhone X iOS 16 userland (plain arm64), ad-hoc signed, running as root over
  SSH.
- The libdrm stand-in that answers Panfrost's DRM ioctls with `HeroGPU`
  calls.
- `osmesa-test`: clear + triangle, pixel check, fps over a few hundred
  frames, on Panfrost and on softpipe (`HERO_GPU=0`).
- Built in the Mac VM (`tools/a51/host/`), reproducible from the repo.

## Non-goals

- EAGL, backboardd, CoreAnimation on the GPU (sub-project 3).
- Showing the triangle on the panel, scanout (sub-project 4); the triangle is
  rendered into memory and checked there.
- Metal (sub-project 5), GLES conformance, performance tuning beyond
  measuring fps.
- Changes to the iOS root image; everything is copied over SSH.

## Anti-goals

- Anything of Apple's in the repository or in build artifacts (SDK headers
  only at build time on the Mac, as for the kernel).
- A phone that no longer boots normally: GPU failures must stay inside the
  test process or end in the panic-reset into TWRP (patch 0143).
- Silent fallback: a run that quietly used softpipe must not be reported as a
  GPU result.

## Constraints

- GPU: Mali-G72 r0p1, `GPU_ID` `0x62210010`, 3 cores, not IO-coherent; Mesa
  25.0.7 lists it (`MODEL(0x6221, 0, "G72", "THEx", 0x0030, 16384, {})`, no
  quirks; anisotropic filtering needs r0p3, so it is off).
- Kernel interface: `HeroGPU`, open type 0, selectors 0 GetParam, 1 CreateBO,
  2 FreeBO, 3 MapBO, 4 Submit (synchronous, 200 ms job limit), 5 Log,
  6 SurfaceBO, 7 SyncBO; one GPU address space; user VA
  `0x40000000–0x7fffffff`; at most 4096 BOs of 256 MiB each.
- Kernel on the phone: boot 42 = kernel143 (0138–0143) with
  `a51gpu=3 a51gpulog=1`; herogpu-test passed on it. Mesa starts there, with
  no boot write. kernel144 (0144: flush id with flush reduction, no stale job
  status) is built but not booted; it is booted (owner approval, like every
  boot write) as soon as a Mesa job faults, so a fault is never chased on a
  kernel with a known job-path defect.
- iOS: arm64 (no arm64e), the SWEET AMFI policy accepts ad-hoc signed
  binaries and dylibs; root shell over SSH at 192.168.7.2.
- Build host: the Mac VM (Intel, macOS 13.7, Xcode 15.2, no Homebrew); GitHub
  macOS runners did not start on 2026-10-28.

## Decided (by the owner or in sub-project 1)

- Approach A from sub-project 1's design: reuse the S7 port's Mesa layer
  (wardevsa/ios-a5xelte `herolte`, `gpu/mesa/`) against the unchanged
  `HeroGPU` interface. Done criterion: triangle + fps.

## The build's shape (my calls, for the owner to check)

1. **Sources:** copy the S7's `gpu/mesa/` (`build-mesa.sh`, `patch-mesa.py`,
   `herodrm.c`, `hero_hw.c`, `osmesa_hero.inc`, `osmesa-test.c`) into
   `gpu/mesa/` here; Mesa `mesa-25.0.7`, libdrm `libdrm-2.4.124`, the S7's
   pins. Changes from the S7: comments and names (Mali-G72, A51), the install
   path (`/private/var/a51gpu/lib` instead of the S7's drop zone
   `/private/var/herolte/lib`; rpath and `ERR_PATH` follow), and nothing
   Midgard-specific left in the patches (checked when porting; Mesa builds
   the Bifrost back end for Panfrost by default).
2. **Build on the Mac VM:** `tools/a51/host/setup-mac-build.sh` gains the
   Mesa tools Homebrew provided on the S7's runner: a Python venv with meson,
   mako, pyyaml, packaging; GNU bison 3.8 from source (macOS ships 2.3);
   pkgconf from source. `tools/a51/host/mac-mesa.sh OUTDIR` copies
   `gpu/mesa/` to the VM, runs `build-mesa.sh` there and fetches `OUTDIR`
   (`lib/libOSMesa.8.dylib`, `lib/libglapi.0.dylib`, `lib/libdrm.2.dylib`,
   `osmesa-test`, `SHA256SUMS`), mirroring `mac-kernel.sh`.
3. **On the phone:** `scp` the dylibs to `/private/var/a51gpu/lib` and
   `osmesa-test` to `/private/var/a51gpu/`; run it over SSH. Its stdout and
   the kernel log (`HeroGPU` Log, job lines with `a51gpulog=1`) both reach the
   PC.
4. **What `osmesa-test` reports:** the renderer string (`GL_RENDERER` must
   name Panfrost / Mali-G72, else the run is a failure, per the anti-goal),
   the pixel check (cleared background + triangle colour at known points),
   frames per second over N frames at 256×256, then the same with
   `HERO_GPU=0` (softpipe) for comparison. Exit 0 only if the GPU run passed.
5. **Kernel limits that may bite:** Mesa asks for a 128 MiB tiler heap; the
   stand-in caps it with `HERODRM_HEAP_MB` (default 32, the S7's). Real
   render jobs may exceed the 200 ms job limit on a cold first frame; a job
   past it is hard-stopped, so Mesa sees a fault, not a slow frame. Raising
   the limit (patch 0145, built with `mac-kernel.sh`, booted with the
   owner's approval) is **in scope** for this sub-project, done only if the
   kernel log shows a job timing out (my call).
6. **Network (checked):** the Mac VM reaches gitlab.freedesktop.org
   (mesa-25.0.7 `081368f8…`, libdrm-2.4.124 `34e9eed6…`), ftp.gnu.org and
   PyPI, so `build-mesa.sh` clones on the VM as on the S7's runner. Bison
   3.8.2, pkgconf 2.3.0 and a venv (`~/mesa-venv`: meson 1.11.2, mako,
   pyyaml, packaging) are installed by `setup-mac-build.sh`.

## Left to the builder

- Exact Mesa meson options beyond the S7's set, if 25.0.7 on Xcode 15.2
  needs any.
- Which S7 `patch-mesa.py` edits are Midgard-only and can go.
- How `osmesa-test` measures time (the S7's `clock_gettime` loop is fine).

## Risks

- Mesa's Bifrost v6 (G72) is less exercised than v7 (G52): a shader or job
  descriptor problem would show as a job fault in the kernel log (status,
  fault address), which `a51gpulog=1` records per job.
- Building Mesa on a 6-core Intel VM may take tens of minutes; the first
  build also builds bison and pkgconf.
- The S7's stand-in was written against `HeroGPU` on a T880; anything that
  assumed Midgard limits (e.g. BO alignment, heap size) shows up at the first
  submit.
