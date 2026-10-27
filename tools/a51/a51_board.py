#!/usr/bin/env python3
"""The A51 board layer, expressed once and used by both
tools/a51/apply-a51.py (a tree already patched to 0124, no git needed) and
tools/a51/mkpatch0125.py (which emits xnu/patches/0125-a51-exynos9611.patch).

Every value is measured, not guessed; the source is the boot-1 shim record in
backup/live/boot6-dmesg-ramoops-0.txt plus backup/live/cmdline.txt and the live
DTB in backup/live/fdt.dtb.
"""

# pexpert/pexpert/arm64/A5XELTE.h: the A51 branch, inserted ahead of the
# dreamlte branch so both boards stay readable in one file.
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
    ' * programming to show framebuffer writes: 1151 FRAME_DONE events in 15 s.',
    ' */',
    '#define A5_FB_PHYS                    0xca000000  /* s3cfb.bootloaderfb, confirmed */',
    '#define A5_FB_WIDTH                   1080',
    '#define A5_FB_HEIGHT                  2400',
    '#define A5_FB_STRIDE                  4320        /* bytes per row, XRGB8888 */',
    '#define A5_FB_2M_BLOCKS               5           /* 1080*2400*4 = 10368000 */',
    '#define A5_ENTRY_MARKER_PHYS          0xf9e9000c  /* pmsg zone data, see below */',
    '#define A5_BOOT_MPIDR                 0x0         /* A53 little cluster boots */',
    '#define A5_KEYS_DEFAULT               1           /* ALIVE GPIO5_15/6_15/7_15 */',
    '#define A5_TOUCH_DEFAULT              0           /* Melfas MMS100: no driver yet */',
    '#define A5_KLOG_PHYS                  0xf9e90000  /* ramoops PMSG zone, not the dump zone */',
    '#define A5_KLOG_SIZE                  0x80000     /* pmsg_size = SZ_512K */',
    '/* The live /timer node carries "use-physical-timer" like the S8, so arm the',
    ' * non-secure physical timer: PPI 14 = INTID 30. a5xelte uses 27 (virtual)',
    ' * only because the Exynos7580 DT lacks that property. */',
    '#define A5_USE_PHYS_TIMER             1',
    '#undef A5XELTE_VTIMER_INTID',
    '#define A5XELTE_VTIMER_INTID         30',
]

# The board selector line and the guard, as they read after 0124.
DREAMLTE_COMMENT = (' * Samsung Galaxy S8 (SM-G950F, dreamlte, Exynos 8895) '
                    'build of this port.')
A51_COMMENT = (' * Samsung Galaxy A51 (SM-A515F, a51, Exynos 9611) build of '
               'this port.')
DREAMLTE_SELECTOR = '#define DREAMLTE                      1'
DREAMLTE_GUARD = '#if defined(DREAMLTE)'
A51_SELECTOR = '#define A51                           1'
A51_GUARD = '#if defined(A51)'
A51_ELSE_GUARD = '#elif defined(DREAMLTE)'

# Why the pmsg zone and not the dump zone for the kernel console ring:
# fs/pstore/ram.c only accepts a DMESG record whose data starts with the ASCII
# header "====<sec>.<nsec>-D\n" (RAMOOPS_KERNMSG_HDR); ramoops_pstore_read()
# calls persistent_ram_zap() on a record without one. pe_serial.c's klog writes
# a bare persistent_ram ring (sig "DBGC", start, size, raw bytes) with no such
# header, so in the dump zone at 0xf9d10000 recovery would discard it. The PMSG
# zone has no header requirement, which is exactly what the S8 port relied on
# (A5_KLOG_PHYS 0x92180000 = "TWRP ramoops pmsg zone"). On this device the zones
# are dump 0xf9d10000, console 0xf9d90000, ftrace 0xf9e10000, pmsg 0xf9e90000,
# all SZ_512K (lib/debug-snapshot-pstore.c), so the kernel log goes to
# 0xf9e90000 and shows up as /sys/fs/pstore/pmsg-ramoops-0.
# The shim keeps its own report in the dump zone *with* a forged "====" header,
# so shim output lands in dmesg-ramoops-0 and kernel output in pmsg-ramoops-0
# without either one clobbering the other.

# Single-line swaps shared by apply-a51.py and mkpatch0125.py so the two routes
# cannot drift. The guard swap is separate because it inserts a whole block.
HEADER_LINE_SUBSTITUTIONS = [
    (DREAMLTE_COMMENT, A51_COMMENT),
    (DREAMLTE_SELECTOR, A51_SELECTOR),
]

# bsd/dev/sweet_ufs.c: the ADT node mkadt_a51.py creates, and the GPT name case
# the A51 actually uses (by-name/userdata -> sda32; the S8 was upper case).
UFS_SUBSTITUTIONS = [
    ('#define UFS_ADT_NODE            "/dreamlte-ufs"',
     '#define UFS_ADT_NODE            "/a51-ufs"'),
    ('#define UFS_DEFAULT_PART        "USERDATA"',
     '#define UFS_DEFAULT_PART        "userdata"'),
]

HEADER_REL = 'pexpert/pexpert/arm64/A5XELTE.h'
UFS_REL = 'bsd/dev/sweet_ufs.c'


def transformed_header(text):
    """Return the A5XELTE.h text with the A51 branch inserted."""
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
