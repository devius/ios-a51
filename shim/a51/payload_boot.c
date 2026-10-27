/* SPDX-License-Identifier: GPL-2.0-only
 * A51 XNU payload handoff: act as iBoot for the SWEETXNU payload that
 * tools/mkpayload.py puts in the boot image's ramdisk.
 *
 * S-Boot decompresses the ramdisk and advertises it through
 * /chosen/linux,initrd-{start,end} (measured on this device: the OrangeFox
 * ramdisk showed up as 0x89000000-0x89edb800), so the payload is found exactly
 * the way the SWEET and a5xelte loaders find it.
 *
 * Layout work is the donor's, proven one: copy each segment to
 * phys_base + (vmaddr - virt_base), put the ADT and then boot_args behind the
 * kernel image, and jump to the entry point with the MMU and caches off and
 * x0 = boot_args physical address.
 *
 * A51 board facts used here are the measured ones: 4 KiB pages, framebuffer
 * 0xca000000 1080x2400 stride 4320, and the kernel RAM window comes from the
 * payload header (tools/mkadt_a51.py sets dram-base 0x880000000).
 */
#include <stdint.h>
#include "report.h"
#include "../fdt.h"

#define BOOT_LINE_LENGTH	608
#define PAGE_SIZE		4096UL

#define FB_PHYS			0xca000000UL
#define FB_WIDTH		1080U
#define FB_HEIGHT		2400U
#define FB_STRIDE		(FB_WIDTH * 4U)

struct payload_seg {
	uint64_t vmaddr, vmsize, file_off, file_size;
};

struct payload {
	char magic[8];
	uint32_t version, nsegs;
	uint64_t virt_base, entry_va, adt_off, adt_size, kernel_end;
	uint64_t phys_base, mem_size;
	char cmdline[BOOT_LINE_LENGTH];
	struct payload_seg segs[];
};

/* pexpert/pexpert/arm64/boot.h, Revision/Version 2 */
struct boot_video {
	uint64_t v_baseAddr, v_display, v_rowBytes, v_width, v_height, v_depth;
};

struct boot_args {
	uint16_t Revision, Version;
	uint64_t virtBase, physBase, memSize, topOfKernelData;
	struct boot_video Video;
	uint32_t machineType;
	uint64_t deviceTreeP;
	uint32_t deviceTreeLength;
	char CommandLine[BOOT_LINE_LENGTH];
	uint64_t bootFlags, memSizeActual;
};

_Static_assert(__builtin_offsetof(struct payload, segs) == 0x2a8, "payload header layout");
_Static_assert(__builtin_offsetof(struct boot_args, Video) == 40, "boot_args layout");
_Static_assert(__builtin_offsetof(struct boot_args, CommandLine) == 108, "boot_args layout");
_Static_assert(sizeof(struct boot_args) == 736, "boot_args layout");

/* MMU off: everything is Device memory, so copy in aligned 8-byte words. */
static void copy64(uintptr_t dst, uintptr_t src, uint64_t n)
{
	volatile uint64_t *d = (volatile uint64_t *)dst;
	volatile const uint64_t *s = (volatile const uint64_t *)src;
	for (uint64_t i = 0; i < (n + 7) / 8; i++)
		d[i] = s[i];
}

static void zero64(uintptr_t dst, uint64_t n)
{
	volatile uint64_t *d = (volatile uint64_t *)dst;
	for (uint64_t i = 0; i < n / 8; i++)
		d[i] = 0;
}

static int magic_ok(const char *m)
{
	static const char want[] = "SWEETXNU";
	for (int i = 0; i < 8; i++)
		if (m[i] != want[i])
			return 0;
	return 1;
}

typedef void (*xnu_entry_t)(uint64_t boot_args_pa);

int payload_present(uintptr_t fdt, uint64_t *rd_start_out)
{
	uint64_t rd_start, rd_end;

	if (!fdt_chosen_u64(fdt, "linux,initrd-start", &rd_start) ||
	    !fdt_chosen_u64(fdt, "linux,initrd-end", &rd_end))
		return 0;
	if (rd_end <= rd_start || rd_end - rd_start < sizeof(struct payload))
		return 0;
	if (!magic_ok(((const struct payload *)(uintptr_t)rd_start)->magic))
		return 0;
	if (rd_start_out)
		*rd_start_out = rd_start;
	return 1;
}

/* Never returns on success. On failure it reports why and returns non-zero so
 * the caller can fall back to the diagnostic dashboard. */
int payload_boot(uintptr_t fdt)
{
	uint64_t rd_start = 0, rd_end = 0;

	if (!fdt_chosen_u64(fdt, "linux,initrd-start", &rd_start) ||
	    !fdt_chosen_u64(fdt, "linux,initrd-end", &rd_end)) {
		rputs("payload: no initrd in /chosen\n");
		return 1;
	}
	rkv("initrd_start", rd_start);
	rkv("initrd_end", rd_end);

	const struct payload *p = (const struct payload *)(uintptr_t)rd_start;
	if (!magic_ok(p->magic)) {
		rputs("payload: no SWEETXNU magic in the ramdisk\n");
		return 2;
	}
	if (p->version != 1 || (p->adt_off & 7) || (rd_start & 7) || !p->nsegs ||
	    p->nsegs > 32) {
		rputs("payload: bad header\n");
		rkv("version", p->version);
		rkv("nsegs", p->nsegs);
		return 3;
	}

	const uint64_t pa_of_va_base = p->phys_base - p->virt_base;
	rkv("phys_base", p->phys_base);
	rkv("virt_base", p->virt_base);
	rkv("mem_size", p->mem_size);
	rkv("entry_va", p->entry_va);
	rkv("kernel_end", p->kernel_end);
	rkv("adt_off", p->adt_off);
	rkv("adt_size", p->adt_size);

	if (rd_end > p->phys_base && rd_start < p->phys_base + p->mem_size) {
		rputs("payload: ramdisk overlaps the kernel window\n");
		return 4;
	}

	for (uint32_t i = 0; i < p->nsegs; i++) {
		const struct payload_seg *s = &p->segs[i];
		uintptr_t dst = (uintptr_t)(s->vmaddr + pa_of_va_base);
		rkv("seg vmaddr", s->vmaddr);
		rkv("seg dst pa", dst);
		rkv("seg file_size", s->file_size);
		rkv("seg vmsize", s->vmsize);
		copy64(dst, (uintptr_t)rd_start + s->file_off, s->file_size);
		if (s->vmsize > s->file_size) {
			uint64_t used = (s->file_size + 7) & ~7UL;
			zero64(dst + used, s->vmsize - used);
		}
	}

	const uintptr_t adt_pa = (uintptr_t)(p->kernel_end + pa_of_va_base);
	copy64(adt_pa, (uintptr_t)rd_start + p->adt_off, p->adt_size);
	const uintptr_t ba_pa = (adt_pa + p->adt_size + PAGE_SIZE - 1) & ~(PAGE_SIZE - 1);
	const uintptr_t top = ba_pa + PAGE_SIZE;
	rkv("adt_pa", adt_pa);
	rkv("boot_args_pa", ba_pa);
	rkv("topOfKernelData", top);

	zero64(ba_pa, PAGE_SIZE);
	volatile struct boot_args *ba = (volatile struct boot_args *)ba_pa;
	ba->Revision = 2;
	ba->Version = 2;
	ba->virtBase = p->virt_base;
	ba->physBase = p->phys_base;
	ba->memSize = p->mem_size;
	ba->topOfKernelData = top;
	ba->Video.v_baseAddr = FB_PHYS;
	ba->Video.v_display = 1;
	ba->Video.v_rowBytes = FB_STRIDE;
	ba->Video.v_width = FB_WIDTH;
	ba->Video.v_height = FB_HEIGHT;
	ba->Video.v_depth = 32;
	ba->machineType = 0;
	/* XNU reads the ADT with the MMU on, so this is a VA, not a PA. */
	ba->deviceTreeP = adt_pa - pa_of_va_base;
	ba->deviceTreeLength = (uint32_t)p->adt_size;
	for (int i = 0; i < BOOT_LINE_LENGTH; i++)
		ba->CommandLine[i] = p->cmdline[i];
	ba->bootFlags = 0;
	ba->memSizeActual = p->mem_size;

	append_marker("jumping to XNU");
	emit_report();
	log_field(20, 10);

	const uintptr_t entry_pa = (uintptr_t)(p->entry_va + pa_of_va_base);
	rkv("entry_pa", entry_pa);

	/* Everything was written with the MMU and caches off; drop stale
	 * I-cache lines so the kernel's own text is what we just copied. */
	__asm__ volatile("dsb sy; ic iallu; dsb sy; isb" ::: "memory");
	((xnu_entry_t)entry_pa)(ba_pa);

	rputs("payload: XNU returned!\n");
	append_marker("xnu returned");
	emit_report();
	return 5;
}
