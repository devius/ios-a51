# A51 GPU, sub-project 1: kernel GPU service (Mali-G72 MP3) — design

Status: approved in conversation (approach, Sections 1–3), 2026-10-29. Next: implementation plan.

## Goal and context

iOS 16.7.16 runs on the Galaxy A51 (SM-A515F, Exynos 9611) up to an
unlockable home screen, with touch, 7 cores, USB Ethernet with a live log, and
SSH. It is slow: CoreAnimation renders on the CPU and every frame is copied
into the DECON command-mode framebuffer.

The owner chose **"both, staged"**: first a smooth system UI over OpenGL ES
(the S7/HackiOS path), then Metal on top. That work is five sub-projects:

| # | Sub-project | Built on | Done when |
|---|---|---|---|
| **1** | **Kernel GPU service** (this document) | S7's HeroGPU (Mali-T880, Midgard), adapted to Bifrost/G72 | A test program in iOS runs a GPU job and gets the right result |
| 2 | Mesa Panfrost (Bifrost compiler) for iOS + the libdrm stand-in that maps Panfrost calls to our IOKit calls | S7 `gpu/mesa` | An OpenGL triangle drawn by the Mali inside iOS, fps measured |
| 3 | CoreAnimation on the GPU: EAGL for backboardd (iOS 16's render server falls back to `CA::OGL::GLESContext` without Metal) | Bergamota / S7 `gpu/eagl` (MIT) | backboardd renders the UI through GLES on the Mali, home-screen fps measured |
| 4 | Frames to the panel without the CPU copy | Redmi Note 12 port's scanout idea + our DECON trigger (patch 0126) | No 10 MB memcpy per frame, smooth scrolling |
| 5 | Metal: AIR → NIR → Bifrost, Metal over Panfrost | Chlorophyll (Adreno), backend swapped for Mesa's Bifrost | Metal effects (blur) and a Metal app work |

## Approach (chosen: A)

- **A — port HeroGPU, adapted to Bifrost (chosen).** The same two layers and
  the same IOKit interface as the S7 (`bsd/dev/herolte_gpu.c`,
  `iokit/Kernel/arm/HeroGPU.cpp`, patches 0225–0249), with Bifrost's MMU
  format, A51 addresses and G72 quirks. Proven on this kernel lineage (Mesa
  triangle at 159 fps inside iOS on the S7); the S7's Mesa glue and the EAGL
  shim were written against this interface, so sub-projects 2–3 become ports.
- B — a fuller Panfrost-DRM clone (per-process address spaces, async jobs,
  sync objects). Several times the work before the first pixel; a later
  upgrade of A that does not change the interface iOS sees.
- C — port ARM/Samsung kbase. Huge, Linux-specific, pairs with ARM's closed
  userland. Not viable.

## Section 1: Hardware bring-up

### Step 0 (done): read-only loader probe, measured on the device

| Register | Value | Meaning |
|---|---|---|
| PMU G3D status (`0x11860000 + 0x4064`) | `0x3000f` | power domain on |
| `GPU_ID` (`0x11500000`) | `0x62210010` | Mali-G72 (product `0x6221`), r0p1 |
| `SHADER_PRESENT` | `0x7` | 3 shader cores (MP3) |
| L2 / tiler present | 1 / 1 | |
| `AS_PRESENT` / `JS_PRESENT` | `0xff` / `0x7` | 8 address spaces, 3 job slots |
| `MMU_FEATURES` | `0x2830` | 48-bit GPU VA, 40-bit PA |
| `COHERENCY_FEATURES` | `0` | not IO-coherent: explicit cache maintenance |
| cores ready | 0 | cores off until powered (normal) |
| `GPU_IRQ_RAWSTAT` | `0x100` | reset completed, idle |

The GPU is powered and clocked at handoff (as on the S7), so no PMU or ACPM
(clock firmware) work is needed. Voltage and clock stay as S-Boot set them.

### Step 1 (kernel): probe and power

A board module for the A51 (guarded like the other A51 code) maps the GPU at
`0x11500000`, reads the same registers only when the PMU G3D status low
nibble is `0xf` (an unpowered block can hang the bus), soft-resets the GPU,
applies the G72 quirks (Section 3), and powers L2, then the 3 shader cores,
then the tiler via the `*_PWRON` registers, with bounded polls on the
`*_READY` registers. Equivalent of the S7's patch 0225. Boot-arg
`a51gpu=0|1|2|3`: 0 skips everything, 1 (default) probes, 2 also powers the
cores, 3 also runs the Step 2 job.

### Step 2 (kernel): first job

One MMU address space (Section 2), then a `WRITE_VALUE` job that writes a
known value into GPU memory; the CPU checks it. Proves power, MMU, job
submission and memory visibility end to end.

## Section 2: MMU and memory

1. **Page-table format: AArch64 4 KB granule**, selected in `AS_TRANSCFG`
   (Midgard's legacy Mali-LPAE format, used by the S7, does not apply). PTEs
   are ARMv8 stage-1 descriptors whose AttrIndx selects a `AS_MEMATTR` slot;
   GPU mappings use a non-cacheable attribute because the GPU is not
   coherent with the CPU caches. Linux Panfrost's Bifrost configuration is
   the reference for `TRANSCFG`/`MEMATTR` values.
2. **One address space (AS0) for everything, HeroGPU's map:**

   | GPU VA | Use |
   |---|---|
   | `0x02000000` | test pages |
   | `0x04000000` | the panel |
   | `0x0a000000` | scratch block |
   | `0x10000000` | present slots (8 MiB each) |
   | `0x40000000–0x7fffffff` | user buffers, L3 tables on demand, VAs reused lowest-first (S7 patch 0249: never-reused VAs exhausted the table pool after ~480 MB) |

   Keeping the map means the S7's user client, Mesa glue and EAGL shim port
   unchanged.
3. **Physical memory: a dedicated GPU region in unused DRAM.** XNU gets
   512 MiB at `0x880000000–0x8a0000000` (ADT `dram-base`/`dram-size`) of the
   2 GiB bank 1, which has no firmware carve-outs. The GPU region is 64 MiB
   at `0x8e0000000` (page tables, scratch block, present slots), outside
   XNU's RAM, so the GPU never competes with iOS for it. If XNU's RAM is
   enlarged later (performance list), this region must stay excluded. User
   buffers stay wired XNU memory, as on the S7 (40-bit PA, reachable).
4. **Cache handling:** CPU mappings of GPU buffers are write-combined; a
   buffer's cacheable kernel alias is cleaned once after zeroing; imported
   IOSurfaces are cleaned and invalidated before GPU use (`SyncBO`).
5. **TLB maintenance:** after every page-table change, Panfrost's sequence:
   lock the region (`AS_LOCKADDR` + `LOCK`), flush (`FLUSH_PT`/`FLUSH_MEM`),
   wait for `AS_STATUS` idle, all bounded.
6. **MMU faults:** `MMU_IRQ_RAWSTAT` is checked after each job; the fault
   status and address of the AS are logged; recovery as in Section 3.

## Section 3: Job submission and the interface to user space

### User-space interface (unchanged from HeroGPU)

IOKit service `HeroGPU` (same name, so the S7's user side finds it), open
type 0:

| # | Call | Arguments → results |
|---|---|---|
| 0 | `GetParam` | Panfrost DRM param → value (`GPU_PROD_ID` = `0x6221`, shader/tiler/L2 present, MMU and job-slot features); Mesa selects its Bifrost (v6) back end from this |
| 1 | `CreateBO` | size → handle, GPU VA, size (wired, GPU VA in the user range) |
| 2 | `FreeBO` | handle |
| 3 | `MapBO` | handle → user address (write-combined) |
| 4 | `Submit` | job-chain VA, slot → status, µs |
| 6 | `SurfaceBO` | IOSurface id → handle, GPU VA, size, bytes per row, width, height, pixel format, offset, planes |
| 7 | `SyncBO` | handle: clean + invalidate an imported surface's CPU caches |

### Kernel side

1. One job at a time under a mutex, polled with a time limit (only
   backboardd uses the GPU in sub-projects 1–4).
2. Slots: 0 fragment, 1 vertex/tiler/compute, 2 unused.
3. Per-job configuration flushes the GPU caches at job start and end (the GPU
   is not coherent), with the flags Panfrost uses on Bifrost.
4. G72 r0p1 quirks from Linux (Panfrost's quirk setup and ARM kbase's
   hardware-issue table for this revision), applied at power-up and after
   every reset; replaces HeroGPU's T880 patch 0243.
5. Fault recovery as HeroGPU's patch 0249: hard-stop a faulted or unfinished
   job; if a slot stays active, soft-reset the GPU and bring it back (cores,
   quirks, AS0 reprogrammed on every job).
6. Each job is logged (slot, status, µs) to the console, behind the boot-arg,
   so it shows in the USB live log.

### Out of scope for sub-project 1

Per-process address spaces, interrupt-driven completion, job queues, GPU
power management (the GPU stays on), DVFS. None changes the interface above.

## Code layout

- `bsd/dev/a51_gpu.c` — hardware layer (port of `herolte_gpu.c`): probe,
  power, reset, quirks, AS0 page tables in AArch64 format, job run, fault
  recovery, the boot-time Step 2 job.
- `iokit/Kernel/arm/HeroGPU.cpp` — the S7's user client, with the A51 board
  guard added; calls into `a51_gpu.c` through the same function names the S7
  layer exports.
- Delivered as kernel patches after 0137 (0138…), built by the existing CI
  (`xnu.yml`).

## Testing ladder

A new kernel is one boot-image write from TWRP (`run-cpus.sh`, a few
minutes; no root-image pull). Steps 1–3 can share one kernel and differ only
in the boot-arg; user-space steps need only SSH (`scp`, run):

1. `a51gpu=1`: probe values in the live log equal the Step 0 table.
2. `a51gpu=2`: L2, 3 shader cores and tiler report ready.
3. `a51gpu=3`: the boot-time `WRITE_VALUE` job completes (`JS_STATUS` done)
   and the CPU reads the expected value; no MMU fault.
4. User-space test program (copied over SSH) opens `HeroGPU`, creates a BO,
   submits the same job through `Submit`, reads the value back through
   `MapBO`. **This is sub-project 1's done criterion.**
5. (Sub-project 2) Mesa's first clear, then a triangle.

## Risks

- G72 quirk values: wrong or missing quirks show as job faults
  (`DATA_INVALID_FAULT` on the S7); mitigated by copying Linux's table for
  this exact revision and logging every job's status.
- Bank-1 region assumption: no firmware carve-out is documented there
  (`A51_PROGRESS.md`, Hardware Map §1); Step 3 writes and reads it through
  the GPU before anything depends on it.
- Mesa's Bifrost v6 (G72) support is less exercised than v7 (G52); this
  affects sub-project 2, not the kernel interface.
