#!/usr/bin/env python3
"""The A51 board layer, expressed once and consumed by both
tools/a51/apply-a51.py (edits a working tree, no git needed) and
tools/a51/mkpatch0125.py (emits xnu/patches/0125-a51-exynos9611.patch).

Everything here is measured on the device, not inferred from the Samsung source
tree; the evidence is the boot-1..8 shim reports in backup/live/ and
A51_PROGRESS.md.

Two kinds of edit:

1. The board block in pexpert/pexpert/arm64/A5XELTE.h. 0124 turned every
   hard-coded A5XELTE constant into an A5_* macro and put the S8 values in a
   `#if defined(DREAMLTE)` branch; we insert an `#if defined(A51)` branch ahead
   of it and flip the board selector, so the S8 stays readable and buildable.

2. Guard extension. 0124 also wrapped its new code in `#if defined(DREAMLTE)`.
   Some of that code is board-neutral and the A51 needs it verbatim (the ramoops
   console copy, the framebuffer VA reservation, the deterministic physmap, the
   CPU_ON trampoline for a high-bank entry). Some of it encodes S8 hardware and
   must stay off (the MPIDR topology, the S6SY761 touch, the S8 logical display
   size, the S8 DECON base). GUARD_SITES below lists, per file, exactly which
   occurrences are extended; the ones left alone fall through to the existing
   `#else`/A5XELTE path, which matches A51 hardware.

3. A5XELTE branch-out where the S8 body needs S8-only symbols. MACHINE_CONFIG
   is still A5XELTE for the A51, so `#if defined(ARM64_BOARD_CONFIG_A5XELTE)`
   selects S8 code. In iokit/Kernel/arm/SweetBattery.cpp that code calls
   dreamlte_battery_read(), whose definition sits in bsd/dev/a5xelte_touch.c
   under `#if defined(DREAMLTE)`; on the A51 that patch never defines it, which
   is the undefined-symbol failure of run 40452629749. A5XELTE_GUARD_SITES puts
   an `#if defined(A51)` branch ahead of the S8 one there.
"""

HEADER_REL = 'pexpert/pexpert/arm64/A5XELTE.h'
UFS_REL = 'bsd/dev/sweet_ufs.c'
KEYS_REL = 'bsd/dev/a5xelte_keys.c'
FB_REL = 'iokit/Kernel/arm/SweetFramebuffer.cpp'
CPU_REL = 'iokit/Kernel/arm/SweetCPU.cpp'
BAT_REL = 'iokit/Kernel/arm/SweetBattery.cpp'
SERIAL_REL = 'pexpert/arm/pe_serial.c'
VMINIT_REL = 'osfmk/arm64/arm_vm_init.c'

# ---------------------------------------------------------------- board block

A51_HEADER_BLOCK = [
    '/*',
    ' * Samsung Galaxy A51 (SM-A515F, a51, Exynos 9611). Measured on hardware by',
    ' * shim/a51 on 2026-10-27: S-Boot hands off at EL1 with the MMU off',
    ' * (SCTLR_EL1 0x30c5083a) on MPIDR 0 (Cortex-A53 little cluster), no EL2/EL3',
    ' * (ID_AA64PFR0_EL1 0x2222), 40-bit PA (ID_AA64MMFR0_EL1 0x1122), CNTFRQ_EL0',
    ' * already 26 MHz, GICD 0x12301000 present but disabled (GICD_CTLR 0),',
    ' * DECON_F 0x148b0000 running in command mode (GLOBAL_CONTROL 0x113) and',
    ' * still scanning 0xca000000 through dpp@0x14881000 (IN_BASE_ADDR_Y, with',
    ' * SRC_SIZE/IMG_SIZE 0x09600438 = 2400x1080). The panel needs no DECON',
    ' * programming to show framebuffer writes: 1901 FRAME_DONE events in 25 s.',
    ' */',
    '#define A5_FB_PHYS                    0xca000000  /* s3cfb.bootloaderfb, confirmed */',
    '#define A5_FB_WIDTH                   1080',
    '#define A5_FB_HEIGHT                  2400',
    '#define A5_FB_STRIDE                  4320        /* bytes per row, XRGB8888 */',
    '#define A5_FB_2M_BLOCKS               5           /* 1080*2400*4 = 10368000 */',
    '#define A5_DECON_PHYS                 0x148b0000  /* DECON_F, not the S8 0x12860000 */',
    '#define A5_ENTRY_MARKER_PHYS          0xf9e9000c  /* pmsg zone data, see below */',
    '#define A5_BOOT_MPIDR                 0x0         /* A53 little cluster boots */',
    '#define A5_KEYS_DEFAULT               0           /* ALIVE is 0x11850000 on 9611, banks 5/6/7 pin 15; Phase 5 */',
    '#define A5_TOUCH_DEFAULT              0           /* Melfas MMS100 on i2c 0x48: no driver yet */',
    '#define A5_KLOG_PHYS                  0xf9e90000  /* ramoops PMSG zone, not the dump zone */',
    '#define A5_KLOG_SIZE                  0x80000     /* pmsg_size = SZ_512K */',
    '/* The live /timer node carries "use-physical-timer" like the S8, so arm the',
    ' * non-secure physical timer: PPI 14 = INTID 30. a5xelte uses 27 (virtual)',
    ' * only because the Exynos7580 DT lacks that property. */',
    '#define A5_USE_PHYS_TIMER             1',
    '#undef A5XELTE_VTIMER_INTID',
    '#define A5XELTE_VTIMER_INTID         30',
]

# Why the pmsg zone and not the dump zone for the kernel console ring:
# fs/pstore/ram.c only accepts a DMESG record whose data starts with the ASCII
# header "====<sec>.<nsec>-D\n" (RAMOOPS_KERNMSG_HDR); ramoops_pstore_read()
# calls persistent_ram_zap() on a record without one. pe_serial.c's klog writes
# a bare persistent_ram ring (sig "DBGC", start, size, raw bytes), so in the dump
# zone at 0xf9d10000 recovery would discard it. The PMSG zone has no header
# requirement -- which is what the S8 port relied on (A5_KLOG_PHYS 0x92180000,
# "TWRP ramoops pmsg zone"). Zone map on this device (lib/debug-snapshot-pstore.c
# sizes, fs/pstore/ram.c order, log_pstore reg 0xf9d10000+0x200000):
#   dump 0xf9d10000  console 0xf9d90000  ftrace 0xf9e10000  pmsg 0xf9e90000
# The shim keeps its own report in the dump zone *with* a forged "====" header,
# so shim output lands in dmesg-ramoops-0 and the kernel log in pmsg-ramoops-0
# without either clobbering the other.

DREAMLTE_COMMENT = (' * Samsung Galaxy S8 (SM-G950F, dreamlte, Exynos 8895) '
                    'build of this port.')
A51_COMMENT = (' * Samsung Galaxy A51 (SM-A515F, a51, Exynos 9611) build of '
               'this port.')
DREAMLTE_SELECTOR = '#define DREAMLTE                      1'
DREAMLTE_GUARD = '#if defined(DREAMLTE)'
A51_SELECTOR = '#define A51                           1'
A51_GUARD = '#if defined(A51)'
A51_ELSE_GUARD = '#elif defined(DREAMLTE)'

HEADER_LINE_SUBSTITUTIONS = [
    (DREAMLTE_COMMENT, A51_COMMENT),
    (DREAMLTE_SELECTOR, A51_SELECTOR),
]

UFS_SUBSTITUTIONS = [
    ('#define UFS_ADT_NODE            "/dreamlte-ufs"',
     '#define UFS_ADT_NODE            "/a51-ufs"'),
    ('#define UFS_DEFAULT_PART        "USERDATA"',
     '#define UFS_DEFAULT_PART        "userdata"'),
]

# ------------------------------------------------------- DREAMLTE guard sites
# (rel, 1-based occurrence of a line starting with "#if defined(DREAMLTE)",
#  replacement lines). Occurrences not listed keep the S8-only behaviour.
GUARD = '#if defined(DREAMLTE)'
BOTH = '#if (defined(DREAMLTE) || defined(A51))'

GUARD_SITES = [
    # Deterministic physmap (no slide) and thetwig rounding: the loader places
    # the kernel in bank 1 and nothing else knows the slide.
    (VMINIT_REL, 1, [BOTH]),
    (VMINIT_REL, 2, ['#if (defined(DREAMLTE) || defined(A51)) && !XNU_MONITOR']),
    # Reserve VA for the scanout buffer: A5_FB_STRIDE*A5_FB_HEIGHT + 64 MiB.
    (VMINIT_REL, 3, [BOTH]),
    # The ramoops console copy - our only readable kernel log on this device.
    (SERIAL_REL, 1, [BOTH]),
    (SERIAL_REL, 2, [BOTH]),
    (SERIAL_REL, 3, [BOTH]),
    # ml_io_map declaration, needed by the CPU_ON trampoline below.
    (CPU_REL, 1, [BOTH]),
    # CPU_REL occurrence 2 is the S8 MPIDR map (logical 0-3 = 0x100-0x103).
    # A51 measured the opposite: A53 = MPIDR 0x0-0x3 boot cluster, A73 =
    # 0x100-0x103, which is exactly the existing #else/A5XELTE branch. Leave it.
    (CPU_REL, 3, [BOTH]),
    # FB_REL occurrence 1 forces the iPhone-X logical size; the A5XELTE path
    # (native 1080x2400) is what we want for the first boots. Leave it.
    # Occurrence 2 is the frame-done wait: needed (DECON fetches at ~76 Hz while
    # we copy), but with the A51 DECON base instead of the S8's.
    (FB_REL, 2, [BOTH,
                 '#ifndef A5_DECON_PHYS',
                 '#define A5_DECON_PHYS 0x12860000UL  /* S8 DECON_F */',
                 '#endif']),
    (FB_REL, 3, [BOTH]),
    # ALIVE pinctrl base: live DTB says /pinctrl@11850000 with gpa0/gpa1/gpa2
    # and the key-power/key-volup/key-voldown states. Keys stay disabled
    # (A5_KEYS_DEFAULT 0) until the bank/pin sampling is worked out.
    (KEYS_REL, 1, ['#if defined(A51)',
                   '#define A5_ALIVE_PA 0x11850000u            /* Exynos 9611 pinctrl ALIVE */',
                   '#elif defined(DREAMLTE)']),
]

# ------------------------------------------- ARM64_BOARD_CONFIG_A5XELTE sites
# Same idea as GUARD_SITES, for code that 0124 put under the S8 *config* guard.
# The A51 builds with MACHINE_CONFIG=A5XELTE, so that guard is true on both
# boards and an A51 branch has to come first.
A5XELTE_GUARD = '#if defined(ARM64_BOARD_CONFIG_A5XELTE)'

A5XELTE_GUARD_SITES = [
    # SweetBattery.cpp occurrence 1: the declaration block. 0124 declared
    # dreamlte_battery_read (S8 MAX77865, defined in a5xelte_touch.c only under
    # DREAMLTE) and stubbed sweet_spmi away. The A51 has no fuel gauge yet --
    # the Melfas MMS100 and the 4000 mAh pack are Phase 5 -- so it declares no
    # gauge function and keeps the SPMI stubs, but with its own capacity.
    (BAT_REL, 1, ['#if defined(A51)',
                  '/* Galaxy A51: no fuel gauge driver yet (Phase 5). */',
                  'static inline int sweet_spmi_init(void) { return -1; }',
                  'static inline int sweet_spmi_read(unsigned, unsigned, uint8_t *) { return -1; }',
                  '#define SWEET_BAT_MAH 4000u',
                  '#elif defined(ARM64_BOARD_CONFIG_A5XELTE)']),
    # poll(): publish the very same unmeasured AC default the S8 branch falls
    # back to, without reading a PMIC or gauge register.
    (BAT_REL, 2, ['#if defined(A51)',
                  '\t/* Unmeasured, like the S8 fallback: 100%, AC, not charging. */',
                  '\tpublish(100, 4200, 0, true, true, false, true, false, false);',
                  '#elif defined(ARM64_BOARD_CONFIG_A5XELTE)']),
    # start(): without a gauge there is nothing to poll, so never arm the 30 s
    # timer and never set fReal (a sweetbattery=1 boot arg stays inert).
    (BAT_REL, 3, ['#if defined(A51)',
                  '\tint real = 0;',
                  '#elif defined(ARM64_BOARD_CONFIG_A5XELTE)']),
    (BAT_REL, 4, ['#if defined(A51)',
                  '\tfReal = false;',
                  '#elif defined(ARM64_BOARD_CONFIG_A5XELTE)']),
]

# Plain substitutions inside a DREAMLTE-guarded body: (rel, old, new), where new
# is either one line or a list of lines that replace the old one.
LINE_EDITS = [
    (FB_REL, 'sweet_fb_decon = ml_io_map(0x12860000, 0x1000);',
     'sweet_fb_decon = ml_io_map(A5_DECON_PHYS, 0x1000);'),
    # A51 is defined in this header. SweetBattery.cpp keyed only off the
    # ARM64_BOARD_CONFIG_* -D flags and never included it.
    (BAT_REL, '#include <pexpert/pexpert.h>',
     ['#include <pexpert/pexpert.h>',
      '#include <pexpert/arm64/board_config.h>']),
]

EDITED_FILES = [HEADER_REL, UFS_REL, VMINIT_REL, SERIAL_REL, CPU_REL, FB_REL,
                KEYS_REL, BAT_REL]


def _extend_guard(line):
    return line.replace('defined(DREAMLTE)', '(defined(DREAMLTE) || defined(A51))')


def transformed_header(text):
    """A5XELTE.h with the A51 branch inserted ahead of the dreamlte one."""
    for old, new in HEADER_LINE_SUBSTITUTIONS:
        if text.count(old) != 1:
            raise SystemExit(f'{HEADER_REL}: expected 1x {old!r}')
        text = text.replace(old, new)
    if text.count(DREAMLTE_GUARD) != 1:
        raise SystemExit(f'{HEADER_REL}: dreamlte guard not found exactly once')
    # The guard is matched without its newline, so the block must not add one.
    block = '\n'.join([A51_GUARD] + A51_HEADER_BLOCK + [A51_ELSE_GUARD])
    return text.replace(DREAMLTE_GUARD, block)


def transformed_ufs(text):
    for old, new in UFS_SUBSTITUTIONS:
        if text.count(old) != 1:
            raise SystemExit(f'{UFS_REL}: expected 1x {old!r}')
        text = text.replace(old, new)
    return text


def transform_lines(rel, lines):
    """Apply GUARD_SITES, A5XELTE_GUARD_SITES and LINE_EDITS for one file.

    lines have no newlines."""
    lines = list(lines)

    # Resolve every target index against the ORIGINAL text first: replacing a
    # guard stops it from matching the pattern, which would shift the numbering
    # of later occurrences. Then apply bottom-up so insertions stay valid.
    lines = _apply_sites(rel, lines, GUARD, GUARD_SITES)
    lines = _apply_sites(rel, lines, A5XELTE_GUARD, A5XELTE_GUARD_SITES)

    for target_rel, old, new in LINE_EDITS:
        if target_rel != rel:
            continue
        hits = [i for i, l in enumerate(lines) if l.strip() == old.strip()]
        if len(hits) != 1:
            raise SystemExit(f'{rel}: expected 1x {old!r}, found {len(hits)}')
        indent = lines[hits[0]][:len(lines[hits[0]]) - len(lines[hits[0]].lstrip())]
        replacement = [new] if isinstance(new, str) else list(new)
        lines[hits[0]:hits[0] + 1] = [indent + l if k == 0 else l
                                      for k, l in enumerate(replacement)]

    return lines


def _apply_sites(rel, lines, pattern, sites):
    """Replace the Nth line starting with pattern with a list of lines."""
    lines = list(lines)
    idxs = [i for i, l in enumerate(lines) if l.startswith(pattern)]
    pending = []
    for target_rel, occ, replacement in sites:
        if target_rel != rel:
            continue
        if len(idxs) < occ:
            raise SystemExit(f'{rel}: only {len(idxs)} {pattern!r} guards, '
                             f'wanted occurrence {occ}')
        i = idxs[occ - 1]
        if replacement == [BOTH]:
            pending.append((i, [_extend_guard(lines[i])]))
        else:
            pending.append((i, list(replacement)))
    for i, replacement in sorted(pending, key=lambda p: -p[0]):
        lines[i:i + 1] = replacement
    return lines


def transformed_file(rel, text):
    """Full transform for one source file (header/ufs handled separately)."""
    if rel == HEADER_REL:
        return transformed_header(text)
    if rel == UFS_REL:
        return transformed_ufs(text)
    nl = '\r\n' if '\r\n' in text else '\n'
    lines = text.split(nl)
    trailing = lines[-1] == ''
    if trailing:
        lines = lines[:-1]
    out = transform_lines(rel, lines)
    if trailing:
        out.append('')
    return nl.join(out)
