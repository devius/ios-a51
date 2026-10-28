# A51 GPU sub-project 3: iOS's UI on the GPU — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** backboardd draws iOS's UI through OpenGL ES on the Mali-G72 (EAGL shim over Mesa), every screen correct, home-screen fps measured before and after.

**Architecture:** Kernel patches 0145 (IOSurface wrap selectors refused), 0146 (an "AMFI" policy answering dyld's query for backboardd, 2-launch guard, `a51gl` switch), 0147 (presents-per-second counter); a 60-minute dead-man loader; the S7's `gpu/eagl` shim built after Mesa on the Mac VM; backboardd's launchd job gets `DYLD_INSERT_LIBRARIES` over SSH.

**Tech Stack:** XNU patches (local tree `~/xnuwork/xnu`, `mac-kernel.sh`), Objective-C/C shim (Bergamota's, MIT), Mesa 25.0.7 (`gpu/mesa`), Python for plist edits, SSH.

**Spec:** `docs/superpowers/specs/2026-10-29-a51-gpu-coreanimation-design.md`

## Global Constraints

- Every boot-partition write needs the owner's approval; reboots without a write do not.
- Shim and Mesa live in `/private/var/a51gpu/lib`; shim `libheroeagl.dylib`.
- Shim starts with `BGL_NODIRECT=1 HERO_GPU_BLIT=0`; direct paths enabled one at a time later.
- dyld policy answer only for process name `backboardd`, only its first 2 launches per boot, never when `a51gl=0`; flags `(1<<0)|(1<<1)|(1<<5)`; every other caller gets `ENOPOLICY` (as with no policy).
- No black areas: Reduce Transparency on for backboardd.
- Nothing of Apple's committed.

## Review Focus

1. **Crash loop:** a shim that kills backboardd must leave a working CPU-rendered UI after 2 launches (0146 guard).
2. **The "AMFI" name:** registering a second MAC policy must not change any check of the existing "A5XELTE AMFI"/"Sandbox" policies (syscall only).
3. **Black panel / wrong format:** `hero_backboardd.c` keeps 8-bit BGRA; a black panel after enabling is the known 'b3a8' failure.
4. **launchd.plist edit corrupting the plist:** the edit tool writes a backup, verifies the binary plist round-trips, and can restore.
5. **fps numbers from the wrong renderer:** "after" must show GPU jobs from backboardd and the shim's rendered-fps lines.

---

### Task 1: Kernel patches 0145–0147

**Files:** `xnu/patches/0145-sweetsurface-refuse-wrap.patch`, `0146-a51-amfi-dyld-policy-backboardd.patch`, `0147-sweetfb-presents-per-second.patch`; check script `tools/a51/gpu/check-gl-patches.sh XNU_TREE`.

- [ ] **Step 1:** Write `check-gl-patches.sh`: (a) `SweetSurface.cpp` `externalMethod` has `case 6:` and `case 7:` returning `kIOReturnUnsupported`; (b) `sweet_amfi.c` registers a policy with `.mpc_name = "AMFI"` whose `mpo_policy_syscall` handles call 90 and returns `ENOPOLICY` otherwise, checks `a51gl`, the name `backboardd`, a launch counter `< 2`, and the three flag bits; (c) `SweetFramebuffer.cpp` has a once-per-second presents counter behind boot-arg `a51fps`. Run → FAIL.
- [ ] **Step 2:** Implement in `~/xnuwork/xnu` (each as its own commit there); 0146's handler: `copyin` `{u64 in; user_addr_t out}`, `copyout` flags (port of S7 0246 `sweet_amfi_dyld_syscall`); count launches by pid change.
- [ ] **Step 3:** `check-gl-patches.sh ~/xnuwork/xnu` → passes; stubbed clang syntax check of `sweet_amfi.c` changes; patches 0138–0147 apply in sequence to the baseline and equal the tree.
- [ ] **Step 4:** `mac-kernel.sh ../build/kernel147` → exit 0, none of ours skipped; `strings` shows the new log lines.
- [ ] **Step 5:** Commit patches + script.

### Task 2: 60-minute dead-man loader

- [ ] **Step 1:** Build `shim/a51` with `CROSS=aarch64-linux-gnu- EXTRA_CFLAGS="-DDEADMAN_MS=3600000UL -DDEADMAN_MPIDR=0x103UL"` → `build/loader-60min.bin`; check it differs from a 15-min build only in the deadline constant (`cmp -l` small, `ARM64 Image header OK`).
- [ ] **Step 2:** Record in `A51_PROGRESS.md`; commit nothing else (binary stays in `build/`).

### Task 3: `gpu/eagl` for the A51

**Files:** `gpu/eagl/**` from the S7 (`build-eagl.sh`, `NOTICE.md`, `src/*`, `test/*`, `tools/gen_gl_stubs.py`); `hero_backboardd.c` + Reduce Transparency; `check-eagl.sh`; `mac-mesa.sh` runs `build-eagl.sh` after `build-mesa.sh`.

- [ ] **Step 1:** `check-eagl.sh`: no `herolte|/private/var/herolte|Galaxy S7's` outside attribution lines; rpath `/private/var/a51gpu/lib`; `hero_backboardd.c` sets `EnhancedBackgroundContrastEnabled`; NOTICE kept. Run → FAIL.
- [ ] **Step 2:** Port (S7 HEAD revision), rename paths, add the Reduce Transparency preference (in the `com.apple.Accessibility` domain, `kCFPreferencesAnyUser`… as `hero_backboardd.c`'s existing calls do for its app domain).
- [ ] **Step 3:** `check-eagl.sh` passes; `mac-mesa.sh ../build/mesa3` → `lib/libheroeagl.dylib`, `eagl_ca_test`; `otool -L` only `@rpath`/system.
- [ ] **Step 4:** Commit.

### Task 4: Boot the new kernel; measure "before" (CPU)

- [ ] **Step 1 (owner approves the boot write):** `KERNEL=kernel147 LOADER=loader-60min.bin ADT=a51-smp1-id.adt EXTRA_ARGS="sweetusb=2 a5fb_keep_on=1 a5fb_noconsole=1 sweetfb_hz=30 a51gpu=3 a51fps=1" ./run-cpus.sh 7 43`.
- [ ] **Step 2:** Confirm GPU boot jobs pass, presents/s lines appear, `A51 GL:` reports the policy registered, UI as before.
- [ ] **Step 3:** Owner swipes home pages for 10 s; record presents/s (median), backboardd CPU (`ps -o time` before/after), screenshot-free description. This is "before".

### Task 5: The shim in backboardd; "after"

**Files:** `tools/a51/sweet-gl-toggle.py on|off|status` (runs on the PC: `ssh cat` the live `/System/Library/xpc/launchd.plist`, edits backboardd's job `EnvironmentVariables` (`DYLD_INSERT_LIBRARIES`, `BGL_NODIRECT`, `HERO_GPU_BLIT`), keeps a backup on the phone, writes back via a temp file + `mv`, verifies the hash and that `plistlib` reads it).

- [ ] **Step 1:** Copy Mesa + shim + `eagl_ca_test` to the phone; run `eagl_ca_test` over SSH → it reports a GLES context on Panfrost and a rendered frame.
- [ ] **Step 2:** `sweet-gl-toggle.py on`; reboot (no write); live log shows `A51 GL: backboardd launch 1 … allowed`, shim's `EAGL` lines, GPU jobs from backboardd.
- [ ] **Step 3:** Owner checks lock screen, home pages, app launch, Control Center, Settings: all icons/text/images, no black/garbage. Each wrong screen → debug (shim trace `EAGL_TRACE_ON`, job faults), fix, rebuild, repeat.
- [ ] **Step 4:** Same 10 s swipe: presents/s, shim rendered-fps, backboardd CPU. This is "after". **Sub-project 3 done** when every screen is correct.
- [ ] **Step 5:** Enable `HERO_GPU_BLIT`, then direct attach (`BGL_NODIRECT=0`), one per reboot, keeping each only if every screen stays correct; record fps per step.
- [ ] **Step 6:** `A51_PROGRESS.md` entry; commit; push.
