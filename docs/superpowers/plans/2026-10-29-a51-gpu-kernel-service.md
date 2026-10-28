# A51 GPU kernel service (sub-project 1) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A user-space program on the A51's iOS opens the `HeroGPU` IOKit service, runs a `WRITE_VALUE` job on the Mali-G72 and reads back the right value.

**Architecture:** Port the Galaxy S7's HeroGPU (patches 0225–0249 of wardevsa/ios-a5xelte `herolte`) as new xnu patches 0138–0140: a hardware layer `bsd/dev/a51_gpu.c` (probe, power, Mali-LPAE page tables for one address space, polled job runs, fault recovery) and the unchanged IOKit user client `iokit/Kernel/arm/HeroGPU.cpp`. Pure page-table and VA-allocator logic lives in a header that is unit-tested on the host.

**Tech Stack:** C/C++ in xnu-8796.141.3 (blacktop darwin-xnu-build, CI `xnu.yml` on macos-14), host `cc` for unit tests, iOS arm64 C test program built with `xcrun --sdk iphoneos` in CI.

**Spec:** `docs/superpowers/specs/2026-10-29-a51-gpu-kernel-service-design.md` (amended: Mali-LPAE, no quirks).

## Global Constraints

- GPU MMIO `0x11500000`; PMU base `0x11860000`, G3D status `+0x4064`; touch GPU registers only when status low nibble is `0xf`.
- GPU region: 64 MiB at PA `0x8e0000000`, outside XNU RAM `0x880000000–0x8a0000000`.
- One address space (AS0), HeroGPU VA map: test `0x02000000`, panel `0x04000000` (reserved, unused), scratch `0x0a000000`, present slots `0x10000000` (reserved, unused), user `0x40000000–0x7fffffff`.
- Page tables: legacy Mali-LPAE, 4 KiB pages, HeroGPU's encoding; never write `AS_TRANSCFG`.
- No configuration quirks (no `GPU_SHADER_CONFIG`/`GPU_TILER_CONFIG`/`GPU_JM_CONFIG` writes).
- `JS_CONFIG_NEXT` = `(8 << 16) | (3 << 8) | (3 << 12) | (1 << 14)`.
- Boot-arg `a51gpu`: 0 nothing, 1 (default) probe, 2 + power cores, 3 + boot-time `WRITE_VALUE` job.
- All A51 code under `#if defined(A51)` inside `ARM64_BOARD_CONFIG_A5XELTE` builds.
- Every poll bounded; a GPU failure logs and returns, it never panics or blocks boot.
- Ask the owner before every boot-partition write. Kernel patches must apply with `git apply --check` (blacktop's build silently *skips* patches that do not).
- Commits end with the session's Co-Authored-By / Claude-Session lines.

## Review Focus

1. **A patch that silently does not apply** (CI `git apply --check` fails → "Skipping patch", build still green): every kernel task checks the CI log for `Applying patch: …/01NN-…` and greps the built kernel for a new string.
2. **`a51gpu=0`** must leave the GPU untouched: no MMIO mapping, no thread (Task 3 test).
3. **GPU domain reported off** (status nibble ≠ `0xf`): probe logs "G3D off" and returns without reading GPU registers (Task 3 test via the forced-off path `a51gpu_pretend_off=1`).
4. **A job that never finishes / faults:** bounded wait, hard-stop, soft-reset recovery, next job still runs (Task 4 test: a deliberately bad job-chain address, then the good `WRITE_VALUE`).
5. **VA exhaustion / reuse:** freed user VAs are reused lowest-first and the L3 pool is not leaked (Task 2 host tests).

---

### Task 1: Local patched xnu tree and patch workflow

**Files:**
- Create: `tools/a51/xnu-local-tree.sh`

**Interfaces:**
- Produces: `tools/a51/xnu-local-tree.sh WORKDIR` → `WORKDIR/xnu` = xnu-8796.141.3 with blacktop's patches (dxb SHA `663906528d1cd5ea8fde7de6f16de73db9511549`) and `xnu/patches/*.patch` applied in the same order and with the same check-or-skip rule as `build.sh`'s `patches()`; one git commit "baseline" after applying; prints `applied N skipped M` and lists skipped patch names. `.sh` stage scripts are not run (they stage libraries, not sources).
- New patches are made in `WORKDIR/xnu`: edit, then `git diff > ../ios-a51/xnu/patches/01NN-name.patch`, then prepend a commit-style description (as 0131/0137).

- [ ] **Step 1:** Write the script (git clone `--depth 1 --branch xnu-8796.141.3` from apple-oss-distributions/xnu; fetch dxb at the SHA; loop `for p in dxb/patches/*.patch` sorted, after copying ours in, `git apply --check` then `git apply`).
- [ ] **Step 2:** Run `bash tools/a51/xnu-local-tree.sh ~/xnuwork`. Expected: `skipped 0` for every `xnu/patches/0*.patch` of ours (blacktop's own may skip; list them), and `grep -c a51_usb_phy_enable ~/xnuwork/xnu/bsd/dev/sweet_usb.c` ≥ 1.
- [ ] **Step 3:** Commit `tools/a51/xnu-local-tree.sh`.

### Task 2: Page-table and VA allocator core, host-tested

**Files:**
- Create: `bsd/dev/a51_gpu_mmu.h` (shipped inside patch 0138; kept in `tools/a51/gpu/a51_gpu_mmu.h` in the repo and copied into the tree by the patch)
- Test: `tools/a51/gpu/test_mmu.c`, run by `tools/a51/gpu/run-tests.sh`

**Interfaces:**
- Produces (all `static inline`, no xnu headers, `stdint.h`/`stdbool.h` only):
  - `uint64_t a51_pte_page(uint64_t pa)` — Mali-LPAE level-3 entry, HeroGPU's encoding `(pa & ~0xfff) | 0x2c1`.
  - `uint64_t a51_pte_table(uint64_t pa)` — table descriptor `pa | 3`.
  - `unsigned a51_pt_index(uint64_t va, unsigned level)` — level 1..3 index (9 bits each, 4 KiB granule).
  - `struct a51_va_pool { uint64_t base, size; uint64_t used[64]; }` (one bit per 64 KiB chunk of the user range); `uint64_t a51_va_alloc(struct a51_va_pool *, uint64_t bytes)` returns 0 when full, lowest-first; `void a51_va_free(struct a51_va_pool *, uint64_t va, uint64_t bytes)`.

- [ ] **Step 1: Write the failing tests** in `test_mmu.c`:

```c
assert(a51_pte_page(0x8e0001abcull) == 0x8e00012c1ull);   /* S7 hgu_set_locked: (pa & ~0xfff) | 0x2c1 */
assert(a51_pte_table(0x8e0003000ull) == 0x8e0003003ull);
assert(a51_pt_index(0x40201000ull, 1) == 1 && a51_pt_index(0x40201000ull, 2) == 1 && a51_pt_index(0x40201000ull, 3) == 1);
struct a51_va_pool p = { .base = 0x40000000, .size = 0x40000000 };
uint64_t a = a51_va_alloc(&p, 0x10000), b = a51_va_alloc(&p, 0x30000);
assert(a == 0x40000000 && b == 0x40010000);
a51_va_free(&p, a, 0x10000);
assert(a51_va_alloc(&p, 0x8000) == 0x40000000);          /* reused lowest-first, rounded to 64 KiB */
assert(a51_va_alloc(&p, 0x40000000) == 0);                /* larger than what is left: fails, no partial take */
```

  Reference for all S7 code: `build/gpuref/` (S7 patches 0225–0250 applied; `bsd/dev/herolte_gpu.c`, `iokit/Kernel/arm/HeroGPU.cpp`).
- [ ] **Step 2:** `bash tools/a51/gpu/run-tests.sh` → FAIL (header missing).
- [ ] **Step 3:** Implement `a51_gpu_mmu.h` (port `hgu_set_locked`/`herolte_gpu_va_alloc`/`hgu_va_free_locked` logic).
- [ ] **Step 4:** `bash tools/a51/gpu/run-tests.sh` → `all mmu tests passed`.
- [ ] **Step 5:** Commit.

### Task 3: Patch 0138 — probe and power (`a51gpu=1|2`)

**Files:**
- Create: `xnu/patches/0138-a51-gpu-probe-power.patch` adding `bsd/dev/a51_gpu.c`, `bsd/dev/a51_gpu_mmu.h`
- Modify (in the patch): `bsd/conf/files` (`bsd/dev/a51_gpu.c standard`), `iokit/bsddev/IOKitBSDInit.cpp` (after `a5xelte_touch_probe();`: `#if defined(A51) extern void a51_gpu_probe(void); a51_gpu_probe(); #endif`)

**Interfaces:**
- Consumes: Task 2 header (included, unused until Task 4).
- Produces: `void a51_gpu_probe(void)`; static `a51_gpu_rd/wr(uint32_t off)`, `bool a51_gpu_powered(void)`, `bool a51_gpu_power(uint32_t pwron, uint32_t ready, uint32_t mask, const char *name)` (port of `hg_power`), `bool a51_gpu_soft_reset(void)`, `bool a51_gpu_cores_on(void)`; globals `vm_offset_t a51_gpu_base`, `a51_gpu_mode` (boot-arg). Log prefix `A51 GPU: `.

- [ ] **Step 1:** Port `hg_probe` (register list = spec's Step 0 table), `hg_power`, `hg_cores_on`; drop PMIC dump, CMU clock report and quirks. Boot-arg test hook `a51gpu_pretend_off=1` makes `a51_gpu_powered()` return false.
- [ ] **Step 2:** Apply on the local tree: `git apply --check` clean; local syntax check not possible without the SDK, so CI is the compiler.
- [ ] **Step 3:** Push to a fork branch, run CI. Expected: log has `Applying patch: …0138-a51-gpu-probe-power.patch`; `strings kernel.development.a5xelte | grep -c 'A51 GPU: '` ≥ 3.
- [ ] **Step 4 (device, owner approves the boot write):** boot with `a51gpu=1`. Expected live-log line `A51 GPU: id 0x62210010 shader 0x7 tiler 0x1 l2 0x1 as 0xff js 0x7 mmu 0x2830 coh 0x0`.
- [ ] **Step 5:** reboot with `a51gpu=2` (same kernel). Expected `A51 GPU: ready shader 0x7 tiler 0x1 l2 0x1`.
- [ ] **Step 6:** `a51gpu=0` → no `A51 GPU:` line at all; `a51gpu=1 a51gpu_pretend_off=1` → `A51 GPU: G3D off (0x…), not touched` and no register lines. iOS reaches the lock screen in every case.
- [ ] **Step 7:** Commit the patch and record the boot results in `A51_PROGRESS.md`.

### Task 4: Patch 0139 — AS0, jobs, recovery, boot-time `WRITE_VALUE` (`a51gpu=3`)

**Files:**
- Create: `xnu/patches/0139-a51-gpu-as0-jobs.patch` (modifies `bsd/dev/a51_gpu.c`)

**Interfaces:**
- Consumes: Task 2 `a51_pte_*`, `a51_pt_index`, `a51_va_*`; Task 3 power functions.
- Produces (exported `extern "C"`-callable, names as the S7 layer so `HeroGPU.cpp` is unchanged): `bool herolte_gpu_up(void)`, `uint32_t herolte_gpu_reg(uint32_t off)`, `uint64_t herolte_gpu_va_alloc(uint64_t bytes)`, `bool herolte_gpu_map(uint64_t va, const uint64_t *pages, unsigned n)`, `void herolte_gpu_unmap(uint64_t va, unsigned n)`, `uint32_t herolte_gpu_submit(unsigned js, uint64_t jc, uint64_t *us)`; `lck_mtx_t a51_gpu_mtx`.

- [ ] **Step 1:** Port `hgp_setup` (AS0 tables in the GPU region at `0x8e0000000`: L1/L2 static, L3 pool for the user range at the region's top, test block and scratch block mapped), `hgp_mmu_flush`/`hgp_as_idle` (lock, `FLUSH_PT`, wait), `hg_run` (with the Global Constraints `JS_CONFIG_NEXT`), `hg_recover`, `hg_job_write_value`; drop present/panel/draw/copy code. Region mapped uncached in the kernel (`ml_io_map` as the S7 did for its scratch block).
- [ ] **Step 2:** Per-job log (spec 3.6): with boot-arg `a51gpulog=1`, every run logs `A51 GPU: job js N status 0x… N us`.
- [ ] **Step 3:** At `a51gpu=3`, run a job chain at an unmapped VA (`0x7ff00000`) first, then `WRITE_VALUE`. Log `A51 GPU: bad job js 1 status 0x… recovered`, then `A51 GPU: write_value ok 0x… in N us` (value and offset as `hg_job_write_value`).
- [ ] **Step 4:** CI as Task 3 Step 3 for 0139.
- [ ] **Step 5 (device, owner approves):** `a51gpu=3 a51gpulog=1`. Expected both lines above, `MMU fault` only for the bad job, lock screen reached.
- [ ] **Step 6:** Commit; record in `A51_PROGRESS.md`.

### Task 5: Patch 0140 — `HeroGPU` user client

**Files:**
- Create: `xnu/patches/0140-a51-herogpu-user-client.patch` adding `iokit/Kernel/arm/HeroGPU.cpp` (S7 final version: `build/gpuref/iokit/Kernel/arm/HeroGPU.cpp`)
- Modify (in the patch): `iokit/conf/files.arm64` (`iokit/Kernel/arm/HeroGPU.cpp optional iokitcpp`), `iokit/KernelConfigTables.cpp` (HeroGPU personality on `IOResources`, guarded `#if defined(ARM64_BOARD_CONFIG_A5XELTE) && defined(A51)`)

**Interfaces:**
- Consumes: Task 4 exports. Selectors 0–7 exactly as the S7 file (0 GetParam, 1 CreateBO, 2 FreeBO, 3 MapBO, 4 Submit, 5 Log, 6 SurfaceBO, 7 SyncBO).
- Produces: IOKit class `HeroGPU`; `GetParam` returns `GPU_PROD_ID` `0x6221` (from `GPU_ID >> 16`).

- [ ] **Step 1:** Copy the S7 file; change only the board guard and remove the `herogpu_selftest` thread start unless `a51gpu>=4`. `SurfaceBO`/`SyncBO` stay (SweetSurface exists in this tree).
- [ ] **Step 2:** CI as before for 0140; `strings` shows `HeroGPU`.
- [ ] **Step 3:** Commit.

### Task 6: User-space test and done criterion

**Files:**
- Create: `tools/ios/herogpu-test.c` (from the S7's `tools/ios/herogpu-test.c`, steps 1–2 only: GetParam, WRITE_VALUE on JS1; drop the Midgard fragment clear), `.github/workflows/ios-tools.yml` (from the S7: builds `tools/ios/*.c` with `xcrun --sdk iphoneos clang -target arm64-apple-ios16.0`, `codesign -s -`, uploads `ios-tools` artifact)

**Interfaces:**
- Consumes: Task 5 selectors.

- [ ] **Step 1:** Port the test; it prints `GPU_PROD_ID 0x6221` and `write_value ok 0x…` / `write_value FAILED status 0x…`, exit 0 only on success.
- [ ] **Step 2:** Run the workflow; download `ios-tools` (curl via API, `-C - --retry 5`, timeouts).
- [ ] **Step 3 (device, kernel with 0138–0140, `a51gpu=2`, owner approves):** `scp -i build/ssh/a51_ed25519 herogpu-test root@192.168.7.2:/var/root/ && ssh … /var/root/herogpu-test`. Expected: `GPU_PROD_ID 0x6221`, `write_value ok`, exit 0. **Sub-project 1 done.**
- [ ] **Step 4:** Commit; `A51_PROGRESS.md` entry; open/update the upstream PR.
