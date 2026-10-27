"""Build a synthetic A5XELTE-patched tree fragment so tools/a51/apply-a51.py can
be exercised without a real xnu checkout."""
import sys
from pathlib import Path

root = Path(sys.argv[1])
(root / 'pexpert/pexpert/arm64').mkdir(parents=True, exist_ok=True)
(root / 'bsd/dev').mkdir(parents=True, exist_ok=True)

hdr = '''#ifndef _PEXPERT_ARM64_A5XELTE_H
#define _PEXPERT_ARM64_A5XELTE_H
#define A5XELTE_VTIMER_INTID         27

/*
 * Samsung Galaxy S8 (SM-G950F, dreamlte, Exynos 8895) build of this port.
 * Same Samsung S-Boot handoff, GIC-400, 26 MHz timer and Cortex-A53 boot
 * cluster as the A5; the board facts that differ are below.
 */
#define DREAMLTE                      1
#if defined(DREAMLTE)
#define A5_FB_PHYS                    0xcc000000  /* s3cfb.bootloaderfb */
#define A5_FB_WIDTH                   1440
#define A5_FB_HEIGHT                  2960
#define A5_FB_STRIDE                  5760        /* bytes per row */
#define A5_FB_2M_BLOCKS               9           /* 1440*2960*4 bytes */
#define A5_ENTRY_MARKER_PHYS          0x920ff000  /* slot in the loader pstore text */
#define A5_BOOT_MPIDR                 0x100       /* first Cortex-A53 */
#define A5_KEYS_DEFAULT               1           /* S8 keys: GPA0/GPA2 */
#define A5_TOUCH_DEFAULT              0           /* A5 ZT7538 path absent */
#define A5_KLOG_PHYS                  0x92180000  /* TWRP ramoops pmsg zone */
#define A5_KLOG_SIZE                  0x80000
#define A5_USE_PHYS_TIMER             1
#undef A5XELTE_VTIMER_INTID
#define A5XELTE_VTIMER_INTID         30
#else
#define A5_FB_PHYS                    0x67000000
#define A5_FB_WIDTH                   1080
#define A5_FB_HEIGHT                  1920
#define A5_FB_STRIDE                  4320
#define A5_FB_2M_BLOCKS               5
#define A5_ENTRY_MARKER_PHYS          0x469ff100
#define A5_BOOT_MPIDR                 0
#define A5_KEYS_DEFAULT               1
#define A5_TOUCH_DEFAULT              1
#endif
#endif /* _PEXPERT_ARM64_A5XELTE_H */
'''
(root / 'pexpert/pexpert/arm64/A5XELTE.h').write_text(hdr)

ufs = '''#if defined(ARM64_BOARD_CONFIG_SWEET) || defined(ARM64_BOARD_CONFIG_A5XELTE)
#define EXYNOS_UFS              1
#define VS_UTRL_NEXUS_TYPE      0x40
#define UFS_WLUN_DEVICE         0xd0
#define UFS_ADT_NODE            "/dreamlte-ufs"
#define UFS_DEFAULT_PART        "USERDATA"
#define PRDT_BYTES(field)       (field)
#else
#define UFS_ADT_NODE            "/sweet-ufs"
#define UFS_DEFAULT_PART        "userdata"
#define PRDT_BYTES(field)       ((field) * 16u)
#endif
'''
(root / 'bsd/dev/sweet_ufs.c').write_text(ufs)
print(f'synthetic tree at {root}')
