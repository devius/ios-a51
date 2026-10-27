/* SPDX-License-Identifier: GPL-2.0-only
 * Samsung Galaxy A51 (SM-A515F, Exynos 9611) boot-1 diagnostic shim.
 *
 * Entry contract: S-Boot has decompressed/copied this Image and jumps to it
 * at EL1 with the MMU and caches off, x0 = FDT physical address.
 *
 * The image is position independent: no absolute relocations are allowed
 * (see build.sh), every address inside is either PC-relative or a physical
 * constant. The only evidence source is the surviving Samsung log RAM; the
 * framebuffer paint is a best-effort bonus because command-mode panels only
 * latch on a TE trigger owned by S-Boot.
 *
 * Log record (little-endian u64), mirrored to all four regions:
 *   0 "A51SHIM1"      1 CurrentEL        2 SCTLR_EL1
 *   3 FDT PA          4 image PA         5 MPIDR_EL1
 *   6 CNTFRQ_EL0      7 CNTPCT_EL0       8 ID_AA64MMFR0_EL1
 *   9 GICD_TYPER     10 UFS version     11 DECON GLOBAL_CONTROL
 *  12 DECON SHADOW_REQ 13 DECON HW_SW_TRIG_CONTROL 14 DECON HW_TE_CNT
 *  15 DSIM STATUS     16 DPP0 IDMA base Y 17 DPP0 IDMA src size
 *  18 DPP0 IDMA enable 19 framebuffer PA 20 stage/state
 *  21 loop counter    22 loops per second (x100)  23 CRC of paint
 */
.section .text.head, "ax"
.global _start
_start:
    b entry
    .long 0
    .quad 0x80000            /* text_offset, same as the stock A51 Image */
    .quad 0                  /* image_size, patched by build.ps1 */
    .quad 0xa                /* flags: 4K pages, free physical placement */
    .quad 0, 0, 0            /* reserved */
    .byte 0x41, 0x52, 0x4d, 0x64   /* "ARM\x64" */
    .long 0

entry:
    msr daifset, #15
    mov x19, x0                  /* FDT */
    mrs x20, CurrentEL
    adr x21, _start
    /* private stack; the header lives at image start, stack after .bss */
    adr x22, a51_stack_top
    mov sp, x22
    mov x0, x19
    mov x1, x20
    mov x2, x21
    bl a51_main                  /* never returns */
halt:
    wfe
    b halt
    .ltorg

.section .data, "aw"
.balign 16
a51_stack:
    .space 8192
a51_stack_top:
