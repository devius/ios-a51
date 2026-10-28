# A51 GPU, sub-project 3: iOS's UI drawn on the GPU (CoreAnimation over Mesa) — design

Status: approved by the owner ("go ahead"), 2026-10-29; builder check answered (calls marked "my call").

## Intent

The owner's words: "everything is slow now, I hope GPU development will make it
look as it is on iPhone". Today iOS 16's render server (backboardd, through
QuartzCore) finds no GPU and draws the whole UI with its CPU rasterizer
(`CA::OGL::SW::scanline`; the S7 port measured 3–16 fps that way). Sub-projects
1–2 made the Mali-G72 usable from iOS: the kernel's `HeroGPU` service and Mesa
Panfrost inside iOS (`osmesa-test`: GPU triangle, pixels exact, no job faults).

This sub-project connects iOS's own renderer to that GPU. iOS 16 still carries
an OpenGL ES path (`CA::OGL::GLESContext`) and falls back to it by itself when
Metal is missing, as long as an `EAGLContext` works; the S7 port supplies one
with Bergamota's EAGL shim (MIT) over Mesa. Goal: the UI draws on the GPU.

## Success (agreed with the owner)

- **Done when:** backboardd renders the UI through OpenGL ES on the Mali-G72
  (kernel log shows its GPU jobs; QuartzCore no longer in the CPU rasterizer),
  **every screen renders correctly**, and **home-screen frames per second are
  measured before and after** on the same boot settings.
- **"Correctly"** means: lock screen, home screen pages, app launch, Control
  Center, Settings show all icons, text and images, no black or garbage areas,
  nothing unreadable. Effects that iOS 16 draws only through Metal (the frosted
  blurs behind Control Center and the dock) may look plainer than on an iPhone.
  A screen that renders wrong is a bug, not "plainer". (The owner asked for a
  recommendation; this is it, and the owner approved writing it up.)
- **Black is a bug** (my call, from the rule above): the S7 saw the Metal-only
  blur behind Control Center render black. backboardd gets iOS's own *Reduce
  Transparency* setting (Accessibility `EnhancedBackgroundContrastEnabled`,
  set like `hero_backboardd.c`'s CA preferences; key checked on the device),
  so those backgrounds are drawn solid instead.
- Not "exactly like an iPhone" yet: that also needs sub-project 4 (no CPU copy
  to the panel, 60 Hz), full CPU clocks, more RAM for iOS, and Metal
  (sub-project 5).

## Non-goals

- Display scanout / removing the 10 MB CPU copy per frame, 60 Hz (sub-project 4).
- Metal, the Metal-only blur effects (sub-project 5).
- CPU frequency, RAM size (performance list).
- Apps using OpenGL ES themselves (only backboardd gets the shim).

## Anti-goals

- A phone that cannot get back to a working UI: the GPU path must be removable
  over SSH (sshd does not depend on backboardd) and by boot-arg in the kernel.
- Anything of Apple's in the repository or artifacts (SDK headers and the
  device's own frameworks only at build or run time).
- Silently staying on the CPU renderer while claiming GPU numbers: the before /
  after measurement must show where the frames were drawn.

## Constraints

- Phone: kernel with 0138–0144 (GPU service; panic → TWRP), boot-args
  `sweetusb=2 a5fb_keep_on=1 a5fb_noconsole=1 sweetfb_hz=30 a51gpu=3`;
  every boot write needs the owner's approval.
- Mesa: `gpu/mesa` (Mesa 25.0.7, libOSMesa + libdrm stand-in), installed in
  `/private/var/a51gpu/lib`, built on the Mac VM (`mac-mesa.sh`).
- Kernel builds on the Mac VM (`mac-kernel.sh`, ~3 min); GitHub runners are not
  available.
- The loader's dead-man timer resets even a healthy boot into TWRP after 15 min.

## Decided

- Approach A (from sub-project 1): port the S7's pieces, unchanged where
  possible. The owner chose speed first, look later (above).

## The design's shape (my calls, for the owner to check)

1. **EAGL shim:** copy the S7's `gpu/eagl/` at its last revision (my call;
   the S7's notes never record a fully correct GPU UI, so its last changes,
   the direct attach / GPU blit into display surfaces, may be untested): it
   starts with those paths **off** (`BGL_NODIRECT=1`, `HERO_GPU_BLIT=0` in
   backboardd's environment) and they are enabled one at a time once every
   screen is correct. Copy it (Bergamota's shim, MIT, with its
   NOTICE; the S7's changes: `eagl_macro_ensure`, `EAGL_TRACE_ON`) into
   `gpu/eagl/`, renamed for the A51 and installed as
   `/private/var/a51gpu/lib/libheroeagl.dylib` (rpath to the Mesa dylibs).
   Built on the Mac VM after Mesa (`mac-mesa.sh` grows the EAGL step).
   Includes the S7's `hero_backboardd.c` (8-bit BGRA display: deep and
   compressed framebuffers off; without it the S7's panel stayed black) and
   the `eagl_ca_test` program (a CARenderer through the shim, runnable over
   SSH before touching backboardd).
2. **Getting the shim into backboardd:** `DYLD_INSERT_LIBRARIES` in
   backboardd's job in `launchd.plist`, edited over SSH (like the sshd job),
   instead of the S7's exec-time environment hook (its patch 0245). dyld only
   honours `DYLD_*` when the kernel's policy named exactly `"AMFI"` allows it
   (`__mac_syscall("AMFI", 90)`); ours is named "A5XELTE AMFI", so the
   variable would be ignored silently. **Kernel patch 0146:** answer that
   query for `/usr/libexec/backboardd` with the S7's flags
   (`ALLOW_AT_PATH | ALLOW_PATH_VARS | ALLOW_FAILED_LIBRARY_INSERTION`), the
   S7's 0246 logic; boot-arg `a51gl=0` answers "restricted" again (the kill
   switch: backboardd then ignores the shim). **Crash-loop guard** (my call,
   the S7's 0245 rule): only the first 2 backboardd launches per boot get
   "allowed"; later launches run without the shim on the CPU renderer, so a
   crash-looping shim cannot keep the UI down. `launchd.plist` is read at
   boot: the variable is edited on the live root over SSH and takes effect at
   the next reboot (a reboot writes no partition and needs no approval; a
   boot write still does).
3. **IOSurface wrap selectors:** **kernel patch 0145**, the SweetSurface part
   of the S7's 0244: `IOSurfaceRootUserClient` selectors 6/7 (wrap client
   image/memory) return `kIOReturnUnsupported` instead of a zeroed success,
   so CoreAnimation takes its copying path (the S7 saw a NULL+0x30 fault).
4. **Loader:** a loader built with a 60-minute dead-man instead of 15
   (`DEADMAN_MS=3600000`, otherwise identical), since panics now reset into
   TWRP by themselves (0143) and UI sessions need more than 15 minutes.
5. **Order on the phone:** (a) boot the new kernel + loader (owner approval)
   with the UI still on the CPU; measure "before"; (b) run `eagl_ca_test`
   over SSH; (c) add the launchd variable, restart backboardd (or reboot),
   check the UI screen by screen; (d) measure "after".
6. **Measuring fps** (my call): two counters, because the kernel logs only
   some swaps and the panel copy runs at `sweetfb_hz=30`: the shim logs
   frames rendered per second every 5 s (`herodrm_log`), and **kernel patch
   0147** makes SweetFramebuffer log presents per second once a second
   (boot-arg-gated). During a fixed gesture (10 s of swiping between home pages, done by the owner, or by a
   scripted touch sequence if one exists by then) count swaps per second
   from the live log, and record backboardd's CPU time (`ps`) and the GPU
   job count (`a51gpulog=1`). Same boot-args before and after.
7. **Recovery:** if backboardd crash-loops with the shim, remove the launchd
   variable over SSH (or boot with `a51gl=0`); a panic resets into TWRP.

## Left to the builder

- Which of the shim's GL entry points iOS 16 actually needs beyond what the
  S7 confirmed (457 macro slots match iOS 16 per Bergamota/S7 notes).
- Exact fps counting script and how many seconds per sample.
- Whether `eagl_ca_test` needs adapting to run over SSH (the S7 ran it as an
  autorun).

## Risks

- iOS 16 picks a display format the GPU path can't write (the S7's 'b3a8'
  black panel); `hero_backboardd.c` is the known fix.
- Kernel job limit (200 ms) or wired-memory use under real UI load; the
  first full-screen frames may be slow; failures show as job faults in the
  log (osmesa-test now fails on them, backboardd will log them).
- The S7 notes 4% JOB_READ_FAULTs before a barrier (0247); ours already
  issues `dsb sy` before every job.
- The 30 Hz panel copy (`sweetfb_hz=30`) caps the visible fps at 30 even if
  the GPU renders faster: the measurement reports render rate and panel rate
  separately.
