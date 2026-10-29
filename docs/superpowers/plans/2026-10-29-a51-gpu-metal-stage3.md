# A51 Metal, stage 3 (Chlorophyll's MTLDevice on iOS 16) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Chlorophyll's `BGMTLDevice` (`gpu/metal/src/bgmtl.m`, an `_MTLDevice` subclass over `libairmetal`) works through Apple's own Metal API on the A51's iOS 16.7: compute, render, and CoreAnimation's Metal renderer offscreen, checked by Chlorophyll's probes on the phone.

**Architecture:** `build-ios.sh` also compiles `bgmtl.m` and the probes for arm64 / iOS 16.0 against `libairmetal.dylib` (stage 2). Each probe runs over SSH from `/private/var/a51gpu/metal`; where iOS 16's Metal differs from iOS 18's, `bgmtl.m` gets `A51:`-commented changes listed in `NOTICE-A51.md`.

**Tech Stack:** Objective-C (manual retain/release, as upstream), Metal private SPI, C; Mac VM build (`tools/a51/host/mac-metal-ios.sh`).

**Spec:** `docs/superpowers/specs/2026-10-29-a51-gpu-metal-design.md` (stage 3). Follows `docs/superpowers/plans/2026-10-29-a51-gpu-metal.md` (stages 1–2, done).

## Global Constraints

- iOS 16.7.16 userland, **arm64** (not arm64e), `-miphoneos-version-min=16.0`.
- Probes are test processes only: nothing registered with the system, nothing injected (that is stage 4).
- No Apple binaries in git; QuartzCore's metallib is read from the phone's own `/System/Library/Frameworks/QuartzCore.framework/default.metallib`.
- Every vendored file changed is listed in `gpu/metal/NOTICE-A51.md`; `check-vendor.sh` stays at exit 0.
- A probe result is the probe's own pass/fail lines, read from its output; no job faults in the kernel log except ones a test provokes.

## Review Focus

1. An `_MTLDevice` method iOS 16 calls that `bgmtl.m` does not implement must not crash silently — `mtl_gap` lists them (Task 3).
2. `_MTLDevice`'s ivar layout differs between iOS 16 (36 ivars) and 18 (50): any direct ivar access in `bgmtl.m` must be checked against 16.7's layout (Task 1, by the probe running at all).
3. A command buffer's completion handler runs off the encoding thread; a GPU fault must reach `MTLCommandBuffer.error` (Task 1's fault case).
4. IOSurface-backed textures (drawables) must render without a CPU copy (Task 4, carenderer probe uses IOSurfaces).
5. Probe processes must exit cleanly (no hang in teardown) so later stages can restart backboardd safely.

---

### Task 1: BGMTLDevice builds and computes (bgmtl_probe)

**Files:** Modify `gpu/metal/build-ios.sh`, `tools/a51/host/mac-metal-ios.sh`; modify `gpu/metal/src/bgmtl.m` only as the probe requires (each change `A51:`-commented).

- [ ] **Step 1:** Add to `build-ios.sh`: `bgmtl.o` (arm64, iOS 16.0, `-fno-objc-arc`) and `bgmtl_probe` linked with `libairmetal.dylib`, `libdrm.2.dylib`, Foundation, Metal, IOSurface; metallibs as upstream `build-probe.sh` makes them.
- [ ] **Step 2:** Run `bgmtl_probe bg_kernels.metallib` on the phone. Expected: whatever iOS 16 breaks first (record it).
- [ ] **Step 3:** Fix each iOS 16 difference in `bgmtl.m` under `A51:` comments.
- [ ] **Step 4:** Run. Expected: all probe checks pass, no unexpected job faults.
- [ ] **Step 5:** Commit `gpu/metal: BGMTLDevice on iOS 16 (bgmtl_probe)`.

### Task 2: render through Metal (bgmtl_render_probe, bgmtl_quad_probe)

- [ ] **Step 1:** Build both probes. **Step 2:** run, record failures. **Step 3:** fix. **Step 4:** all checks pass (P1–P5 of render_probe; quad_probe's flat-varying check). **Step 5:** commit.

### Task 3: API completeness against iOS 16.7 (mtl_gap)

- [ ] **Step 1:** Build `mtl_gap`. **Step 2:** run on the phone; save its list to `gpu/metal/results/ios16.7-mtl-gap.md`. **Step 3:** implement each missing method QuartzCore uses (cross-check with `strings` of QuartzCore in `build/dsc`), others answered with a logged refusal. **Step 4:** re-run: no method QuartzCore calls is missing. **Step 5:** commit.

### Task 4: CoreAnimation's Metal renderer offscreen (bgmtl_carenderer_probe)

- [ ] **Step 1:** Build `bgmtl_carenderer_probe` (+QuartzCore, CoreGraphics). **Step 2:** run; record. **Step 3:** fix. **Step 4:** the probe's comparison against CA's CPU renderer passes. **Step 5:** commit; `A51_PROGRESS.md` stage 3 results.
