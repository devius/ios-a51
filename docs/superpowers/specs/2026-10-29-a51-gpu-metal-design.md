# A51 GPU, sub-project 4: Metal on the Mali (Chlorophyll over Panfrost) — design

Status: written on defaults; the owner said "dont ask me, go on" (2026-10-29), so
every choice below not quoted from the owner is my call.

## Intent

The owner's words: "everything is slow now, I hope GPU development will make it
look as it is on iPhone", and "can we look how others achieved butter smooth
ui?". The answer from that research, now measured on our phone:

- iOS 16's CPU renderer draws the home screen at **~3 fps** (boots 43 and 47),
  and freeing CPU elsewhere did not change it (boot 47: idle load 21 → 3.1 after
  removing crash loops, swipes still 2–5 fps). Drawing is the bottleneck.
- The OpenGL ES route (sub-project 3, paused) is the slow path others measured
  at 4–26 fps; on our phone it rendered wrongly.
- Bergamota (Poco F1, iOS 18) reached **~45 fps home-screen swipes** with
  Chlorophyll, a Metal driver: Apple's Metal shaders (AIR) → Mesa NIR → the GPU
  compiler, under Metal's own API, so QuartzCore uses its normal Metal renderer.

This sub-project gives iOS a Metal device on the Mali-G72, so backboardd
renders the UI with QuartzCore's Metal renderer on the GPU.

## Why this is feasible on iOS 16 (research, 2026-10-29)

- Chlorophyll's AIR reader and frontend were written against **iOS 16.5**
  (hackios): `air/air_metallib.c:9`, `air_module.h:9-11`. Our iOS 16.7
  QuartzCore `default.metallib` is the same plain `MTLB` v1.2 (checked: header
  `4d 54 4c 42 01 00 02 00`), 141 functions; hackios translated 135 of them.
- iOS 16.7's Metal.framework has the same device hooks (`MTLAddDevice`,
  `MetalPluginName`/`MetalPluginClassName` on `IOAcceleratorES`,
  `-[_MTLDevice initWithAcceleratorPort:]`) and every private init selector
  Chlorophyll calls. `_MTLDevice` has fewer methods on 16.7 (524) than on 18
  (598).
- Chlorophyll is built on **Mesa 25.0.7**, the version we already build for iOS.
- Hardware-specific code is small: Gallium screen creation and IOSurface import
  in `air/air_metal.c` (`#ifdef GALLIUM_FREEDRENO`), plus 9 freedreno/ir3 Mesa
  patches. The rest (~21k lines: AIR→NIR, `src/bgmtl.m`, inject, probes) is
  generic.
- Ruled out: Metal over Vulkan, because Mesa's PanVK refuses our Mali
  generation (v6 < v10, `panvk_physical_device.c:954`); and upgrading to iOS 18,
  because Bergamota's needs a separate XNU and a PAC rewrite of the arm64e
  cache (a second port).

## Success

- **Done when:** backboardd renders the UI through QuartzCore's Metal renderer
  on the Mali (kernel log shows its GPU jobs; QuartzCore not in
  `CA::OGL::SW`), **every screen renders correctly**, and **home-screen swipes
  run at 30 fps or more** (median of the per-second `a51fps` counts during a
  10 s swipe), measured against today's ~3 fps on the same boot settings.
- **"Correctly"** as in sub-project 3: lock screen, home screen pages, app
  launch, Control Center, Settings show all icons, text and images; no black or
  garbage areas. Here the frosted blurs should work too, since they are Metal
  shaders.
- 30 fps is my call: Bergamota's 45 fps was on a stronger GPU (Adreno 630) with
  a 60 Hz path. The panel runs `sweetfb_hz=30` today, so 30 is also our
  display's ceiling until that changes. Above 30 fps belongs to later work.

## Non-goals

- Metal for apps (games, camera): only backboardd's compositor, plus what
  SpringBoard and the wallpaper process need to draw the UI. The plugin-bundle
  route that gives every process Metal is a later stage, not done here.
- iOS 18, Vulkan, OpenCL, CoreML on the GPU.
- Polishing the GLES/EAGL path (paused, kept as is).

## Anti-goals

- **A phone that no longer reaches a usable UI.** Each Metal stage has an off
  switch file read at backboardd start (like `gl-on`), and Chlorophyll's own
  fallback to the CPU renderer stays on. A crash loop of backboardd must end in
  the CPU renderer, not a black screen.
- **Hitches that feel worse than slow-but-steady**: compiling shaders during a
  swipe. Shader translation results are cached on disk (the builder decides how,
  following Chlorophyll if it already has a cache).
- **Hidden GPU faults**: a faulted job is an error the probes report (as
  `herodrm` does since sub-project 2), never a silently wrong frame.

## Constraints

- Userland: unmodified iPhone X iOS 16.7.16 (iPhone10,3), **arm64, not arm64e**.
- Mesa 25.0.7 with our Panfrost port (`gpu/mesa/`: `herodrm.c`, `hero_hw.c`)
  over the kernel's HeroGPU service; builds in the macOS VM
  (`tools/a51/host/mac-mesa.sh`, `mac-kernel.sh`).
- Chlorophyll is MIT ("OOSEX GANG", `LICENSE.hackios-userland`): vendor it as
  `gpu/metal/` at commit `787338fc7c29`, with its licence and a NOTICE that
  says what we changed, as `gpu/eagl/NOTICE.md` does.
- No Apple binaries or metallibs in git (extract them from the device or the
  IPSW when needed, as Chlorophyll's `tools/extract-metallibs.sh` does).
- Kernel changes are new patches 0154 and up on top of 0138–0153, checked by
  applying them in sequence to a clean tree.
- Device installs go to `/private/var/a51gpu/` (readable by `mobile`); the
  kernel-side dylib insertion of patch 0148 is the way into backboardd
  (launchd strips `DYLD_*`).

## The design's shape (my calls)

Stages, each ending in something checked on the phone or the PC:

1. **Shader corpus on the PC (no phone).** Build Chlorophyll's host tools
   against our Mesa tree with the Panfrost (Bifrost) compiler instead of ir3,
   and run `tools/corpus.py` over iOS 16.7's QuartzCore and CoreImage metallibs.
   Output: how many functions translate to NIR and how many Bifrost compiles,
   with the failures listed. Gate: QuartzCore at least 135 of 141, matching
   hackios; failures in functions CoreAnimation uses become compiler work items.
2. **Panfrost back end.** In `air_metal.c`, a `GALLIUM_PANFROST` branch beside
   freedreno's: screen from `panfrost_create_screen` over `herodrm` (as
   `gpu/mesa/osmesa_hero.inc` does); IOSurface import through HeroGPU's
   `SurfaceBO` as a linear `winsys_handle` (`DRM_FORMAT_MOD_LINEAR`). Drop the
   freedreno framebuffer-fetch workarounds: Panfrost reads framebuffers natively
   (`pan_screen.c:593`). None of the 9 freedreno/ir3 Mesa patches is carried
   over.
3. **Probes on the phone.** Chlorophyll's `bgmtl_probe` (compute),
   `bgmtl_quad_probe` and `bgmtl_render_probe` run on the Mali with exact
   pixels, then `bgmtl_carenderer_probe` (a CARenderer drawing layers through
   our Metal device). Also re-run the API completeness check (`mtl_gap.m`)
   against iOS 16.7's `MTLDeviceSPI` and fill what it reports.
4. **backboardd on Metal.** The inject dylib (`inject/bgmtl_inject.m`:
   `MTLAddDevice`, the framebuffer-compression preferences) goes into backboardd
   through patch 0148's mechanism, with a new switch file
   `/private/var/a51gpu/mtl-on` (exclusive with `gl-on`). A tool like
   `sweet-gl-toggle.py` turns it on and off over SSH. Measure fps and check
   every screen. SpringBoard/wallpaper (PosterBoard) get the same inject only
   if the screens need them.
5. **Kernel speed-ups (in parallel with 2–4).** HeroGPU today waits for each job
   before returning. Add asynchronous submit returning a fence number, a
   fence wait with timeout, and job-done interrupts instead of polling; then a
   GPU copy to the panel instead of the CPU copy (SweetFB). Bergamota measured
   these at about 2× (20.8 → 38.6 fps). Herodrm maps them to Panfrost's
   syncobj ioctls.

Order is 1 → 2 → 3 → 4, with 5 started once stage 3 shows real job rates.
Stage 1 decides the plan before any phone work: if the Bifrost compile rate is
far below ir3's, the plan's next task is the compiler failures.

## Left to the builder

- How the shader cache is keyed and stored.
- The exact fence and interrupt interface in HeroGPU and herodrm, as long as
  Panfrost's syncobj semantics hold and sub-project 2's `osmesa-test` keeps
  passing.
- Which Chlorophyll probes, tools and docs are vendored, and which are dropped
  as Adreno-only.
- Whether stage 5's GPU panel copy reuses SweetFB's existing buffers or adds
  a new one.

## Risks

- **Bifrost compiler bugs on Metal-shaped shaders.** Bergamota hit three in
  ir3. Stage 1 finds them on the PC before any device work.
- **Weaker GPU:** Mali-G72 MP3 is behind Adreno 630. If 30 fps is out of reach
  after stage 5, the fallback levers are lower render resolution and the
  CPU clocks (bootloader left the A73s at 1456 of 2300 MHz).
- **RAM:** iOS sees 512 MiB. Metal textures and shader caches add pressure;
  watch jetsam kills in the log during stage 4.
- **iOS 16 API differences** beyond what the completeness check finds (e.g.
  `_MTLResource`'s base class differs on 16): crashes inside QuartzCore at
  stage 3–4, debugged with the probes before backboardd.
