/*
 * MMU setup for 4 KiB pages on Exynos 9611 (A51)
 * Based on Linux aarch64 MMU tables
 */

#include <stdint.h>
#include <string.h>

#define PAGE_SIZE 4096UL
#define PAGE_SHIFT 12UL

struct stage1_page_table {
    uint64_t entries[512];
};

struct stage2_page_table {
    uint64_t entries[512];
};

static struct stage1_page_table __attribute__((aligned(PAGE_SIZE))) stage1_table;
static struct stage2_page_table __attribute__((aligned(PAGE_SIZE))) stage2_table;
static uint64_t __attribute__((aligned(PAGE_SIZE))) zero_page[512];

static void set_pte(uint64_t *table, uint64_t va, uint64_t pa, int flags)
{
    uint64_t index = (va >> PAGE_SHIFT) & 0x1ff;
    table[index] = pa | flags;
}

uintptr_t init_4k_mmu(uintptr_t dram_base, uint64_t dram_size)
{
    /* Clear tables */
    memset(&stage1_table, 0, sizeof(stage1_table));
    memset(&stage2_table, 0, sizeof(stage2_table));
    memset(zero_page, 0, sizeof(zero_page));

    /* Level 1 mapping: map first 4 GiB */
    for (uint64_t i = 0; i < 512; i++) {
        uint64_t va = i << 30;
        uint64_t pa = va;
        if (va >= dram_base && va < (dram_base + dram_size)) {
            /* Stage 2 table for this region */
            set_pte(&stage1_table.entries, va, (uintptr_t)&stage2_table, 0x3);
        } else {
            /* Identity map to zero page */
            set_pte(&stage1_table.entries, va, (uintptr_t)zero_page, 0x3);
        }
    }

    /* Level 2 mapping: detailed 4 GiB regions */
    for (uint64_t i = 0; i < 512; i++) {
        uint64_t va = i << 21;
        uint64_t pa = (va & ~((1UL << 30) - 1)) + (i << 21);
        if (va >= dram_base && va < (dram_base + dram_size)) {
            /* Map the actual DRAM */
            for (uint64_t j = 0; j < 512; j++) {
                uint64_t va_sub = va + (j << 12);
                uint64_t pa_sub = pa + (j << 12);
                if (va_sub >= dram_base && va_sub < (dram_base + dram_size)) {
                    set_pte(&stage2_table.entries, va_sub, pa_sub, 0x3);
                } else {
                    set_pte(&stage2_table.entries, va_sub, (uintptr_t)zero_page, 0x3);
                }
            }
        } else {
            /* Map to zero page */
            for (uint64_t j = 0; j < 512; j++) {
                uint64_t va_sub = va + (j << 12);
                set_pte(&stage2_table.entries, va_sub, (uintptr_t)zero_page, 0x3);
            }
        }
    }

    /* Flush caches */
    __asm__ volatile("dsb sy" : : "memory");
    __asm__ volatile("ic ivac, %0" : : "r" (&stage1_table));
    __asm__ volatile("ic ivac, %0" : : "r" (&stage2_table));
    __asm__ volatile("ic ivac, %0" : : "r" (zero_page));
    __asm__ volatile("dsb sy" : : "memory");

    /* Set up translation tables */
    __asm__ volatile(
        "msr ttbr0_el1, %0" :: "r" ((uintptr_t)&stage1_table)
    );

    /* Set up MMCR_EL1 for 4K pages */
    __asm__ volatile(
        "mrs x0, mair_el1\n"
        "orr x0, x0, #0xff\n"
        "msr mair_el1, x0\n"
        "mov x0, #0x1f\n"
        "msr tcr_el1, x0\n"
        "msr ttbr0_el1, %0\n"
        "dsb sy\n"
        "isb\n"
        :: "r" ((uintptr_t)&stage1_table)
    );

    /* Enable MMU */
    __asm__ volatile(
        "mrs x0, sctlr_el1\n"
        "orr x0, x0, #0x1\n"
        "orr x0, x0, #0x8\n"
        "orr x0, x0, #0x40\n"
        "orr x0, x0, #0x4000\n"
        "msr sctlr_el1, x0\n"
        "dsb sy\n"
        "isb\n"
    );

    return (uintptr_t)&stage1_table;
}