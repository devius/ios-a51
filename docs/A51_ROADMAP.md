# Galaxy A51 iOS port — roadmap and open bugs

The owner's goal: "everything is slow now, I hope GPU development will make it look as it is on iPhone".
Updated 2026-10-29. Progress details: `A51_PROGRESS.md`; designs and plans: `docs/superpowers/`.

## Where we are

- iOS 16.7.16 boots to a usable UI: touch, 7 cores, USB networking, SSH, correct clock, `reboot` over SSH.
- Idle CPU load ~3 (was ~20: crash-looping daemons removed, RTC clock, key-store loop fixed).
- The UI is still drawn by the CPU: ~3 fps home-screen swipes.
- GPU: kernel service (HeroGPU) + Mesa Panfrost (GL 470 fps on a test triangle); Metal via Chlorophyll works
  in test processes, including CoreAnimation's own renderer offscreen (stages 1–3).

## Order of work

1. **Stage 4 — CoreAnimation on Metal in backboardd** (now). The real screen through the Mali, with an off
   switch back to the CPU renderer. Measure swipe fps; look at every screen.
2. **Fix the open bugs below** that stage 4 shows on screen, most visible first.
3. **Stage 5 — speed**: asynchronous GPU submit with fences and interrupts in HeroGPU, GPU copy to the panel
   (Bergamota: ~2x), then the panel at 60 Hz.
4. **CPU clocks** (A73s at 1456 of 2300 MHz, A53s at 1053 of 1700): ACPM DVFS.
5. **More RAM for iOS** (XNU sees 512 MiB).

## Open bugs (must come back to these)

### Metal / GPU
| # | Bug | Where we are | Next step |
|---|---|---|---|
| M1 | **Blur renders black** (CARenderer probe scene 5) in every build that contains the fbfetch-preload Mesa edit, even with it switched off at run time (`A51_NO_FBREAD_PRELOAD=1`); fine without the edit | First wrong draw: the first blur downsample samples the 258x258 offscreen and writes 0. Same shader, uniforms and descriptor addresses as the good build. Suspect layout-dependent UB (uninitialised state, stale texture view) | Sanitizer (ASan/UBSan) build of the host tool on the blur shaders; full pandecode of the blur batches; a51_ca_replay of the downsample |
| M2 | **Faint dashed outline** on rounded-clip edges (scene 3, diff 0.52) | Edge anti-aliasing lines visible in colour 0 | Per-draw probe on an edge pixel |
| M3 | **Layer contents upside down** in the offscreen probe (images, text) | Our textures keep row order (a51_texrows_probe); CoreAnimation's own texcoords give v=1 at the top for CARenderer → MTLTexture | Check on the real screen (stage 4, drawables) before changing anything |
| M4 | Mesa Bifrost: CLPER packing asserts on G72 (`compute_apl_fast`, subgroup shuffles) | Release builds compile it into undefined code | Fix the packer for v6 or lower subgroup ops differently |
| M5 | Mesa Bifrost: 16-bit image stores assert `type size == 32` (23 functions: tile kernels, CoreImage) | Not on the home-screen path | Widen 16-bit image stores to 32 bits in air_metal's finalize |
| M6 | Shader translator: `fixed_frag_lph_cph/cpf` with all-zero constants, `air.thread_index_in_quadgroup`, pointer phis, a repacking bitcast, `air.pack.unorm4x8` | Specialised variants compile at run time; the rest are unused by CA so far | Fix in the AIR frontend when a screen needs them |
| M7 | Review minors (stages 1–2 ledger): `%u` for size_t, unused `sweet_drm_surface_bo` leaks a descriptor, duplicated structs instead of a shared header, test default paths, hidden patch-check failure, `ir3_ok` JSON keys | Deferred | One cleanup pass |
| M8 | GPU fault → `MTLCommandBuffer.error` not covered by a test | Faults reach rwa_finish (tested) | Add to a probe |

### System
| # | Bug | Next step |
|---|---|---|
| S1 | Red "rdar:45025538" status-bar banner (no status-bar layout for 1080x2400) | Present the panel as 1125x2436 (S7 port's 0236) |
| S2 | Time zone shows PDT | Set the zone (`/var/db/timezone/localtime`) |
| S3 | The 60-minute dead-man loader cuts long sessions into TWRP | Build a 4-hour loader (panics and `reboot` already work) |
| S4 | Keychain not protected at rest (aks wrap/unwrap answered without a SEP) | Accept for a test phone, or derive a key from a device secret |
| S5 | The upstream PR (nickdemon22/ios-a51#2) has none of the GPU work | Open a follow-up PR when stage 4 works |
