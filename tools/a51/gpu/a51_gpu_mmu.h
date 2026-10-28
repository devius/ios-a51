/*
 * A51 GPU (Mali-G72): pure page-table and GPU-VA helpers for bsd/dev/a51_gpu.c.
 * No kernel headers, so tools/a51/gpu/test_mmu.c tests them on the host.
 *
 * Page tables are the legacy Mali-LPAE format with 4 KiB pages, as the S7's
 * HeroGPU and Linux Panfrost (ARM_MALI_LPAE) use them: 3 levels of 512
 * entries, L1 1 GiB, L2 2 MiB, L3 4 KiB. Encodings from herolte_gpu.c.
 *
 * User buffers get VAs in 64 KiB chunks from a bitmap, lowest free run
 * first, so freed VAs are reused and the L3 tables stay few (S7 patch 0249:
 * never reusing VAs exhausted its table pool after ~480 MB).
 */
#ifndef A51_GPU_MMU_H
#define A51_GPU_MMU_H

#include <stdbool.h>
#include <stdint.h>

#define A51_VA_CHUNK    0x10000ull
#define A51_VA_CHUNKS   16384u          /* 1 GiB of user range */

/* Level-3 entry for a 4 KiB page: read, write, inner shareable, access flag. */
static inline uint64_t
a51_pte_page(uint64_t pa)
{
	return (pa & ~0xfffull) | 0x2c1;
}

/* Level-1/2 entry pointing at the next table. */
static inline uint64_t
a51_pte_table(uint64_t pa)
{
	return pa | 3;
}

/* Index of va in the level 1..3 table. */
static inline unsigned
a51_pt_index(uint64_t va, unsigned level)
{
	return (unsigned)((va >> (12 + 9 * (3 - level))) & 0x1ff);
}

struct a51_va_pool {
	uint64_t base, size;
	uint64_t used[A51_VA_CHUNKS / 64];
};

static inline bool
a51_va_chunk_used(const struct a51_va_pool *p, unsigned c)
{
	return (p->used[c / 64] >> (c % 64)) & 1;
}

/* Lowest free run of chunks covering bytes; 0 when none (nothing is taken). */
static inline uint64_t
a51_va_alloc(struct a51_va_pool *p, uint64_t bytes)
{
	unsigned chunks = (unsigned)(p->size / A51_VA_CHUNK);
	uint64_t n = (bytes + A51_VA_CHUNK - 1) / A51_VA_CHUNK;
	if (n == 0 || n > chunks) {
		return 0;
	}
	unsigned run = 0;
	for (unsigned c = 0; c < chunks; c++) {
		if (a51_va_chunk_used(p, c)) {
			run = 0;
		} else if (++run == n) {
			unsigned first = c + 1 - (unsigned)n;
			for (unsigned k = first; k <= c; k++) {
				p->used[k / 64] |= 1ull << (k % 64);
			}
			return p->base + first * A51_VA_CHUNK;
		}
	}
	return 0;
}

/* Give back the chunks covering [va, va + bytes); outside the pool: ignored. */
static inline void
a51_va_free(struct a51_va_pool *p, uint64_t va, uint64_t bytes)
{
	if (va < p->base || va >= p->base + p->size || bytes == 0) {
		return;
	}
	unsigned chunks = (unsigned)(p->size / A51_VA_CHUNK);
	unsigned first = (unsigned)((va - p->base) / A51_VA_CHUNK);
	uint64_t count = (bytes + A51_VA_CHUNK - 1) / A51_VA_CHUNK;
	for (uint64_t k = first; k < first + count && k < chunks; k++) {
		p->used[k / 64] &= ~(1ull << (k % 64));
	}
}

#endif /* A51_GPU_MMU_H */
