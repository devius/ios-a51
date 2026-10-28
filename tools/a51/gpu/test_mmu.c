/* Host tests for bsd/dev/a51_gpu_mmu.h (page-table encoding, VA allocator). */
#include <assert.h>
#include <stdio.h>
#include "a51_gpu_mmu.h"

static void
test_pte_encoding(void)
{
	/* S7 hgu_set_locked: (pa & ~0xfff) | 0x2c1; tables pa | 3 */
	assert(a51_pte_page(0x8e0001abcull) == 0x8e00012c1ull);
	assert(a51_pte_table(0x8e0003000ull) == 0x8e0003003ull);
}

static void
test_pt_index(void)
{
	assert(a51_pt_index(0x40201000ull, 1) == 1);
	assert(a51_pt_index(0x40201000ull, 2) == 1);
	assert(a51_pt_index(0x40201000ull, 3) == 1);
	assert(a51_pt_index(0x7fffffffull, 2) == 511 && a51_pt_index(0x7fffffffull, 3) == 511);
}

static void
test_va_lowest_first_reuse(void)
{
	struct a51_va_pool p = { .base = 0x40000000, .size = 0x40000000 };
	uint64_t a = a51_va_alloc(&p, 0x10000), b = a51_va_alloc(&p, 0x30000);
	assert(a == 0x40000000 && b == 0x40010000);
	a51_va_free(&p, a, 0x10000);
	assert(a51_va_alloc(&p, 0x8000) == 0x40000000);          /* reused, rounded to 64 KiB */
	assert(a51_va_alloc(&p, 0x40000000) == 0);                /* more than is left: no partial take */
	assert(a51_va_alloc(&p, 0x10000) == 0x40040000);          /* failed alloc took nothing */
}

static void
test_va_whole_range(void)
{
	struct a51_va_pool p = { .base = 0x40000000, .size = 0x40000000 };
	assert(a51_va_alloc(&p, 0x40000000) == 0x40000000);       /* all 16384 chunks */
	assert(a51_va_alloc(&p, 0x10000) == 0);
	a51_va_free(&p, 0x7fff0000, 0x10000);                     /* last chunk */
	assert(a51_va_alloc(&p, 0x10000) == 0x7fff0000);
	assert(a51_va_alloc(&p, 0) == 0);                         /* zero bytes: nothing */
	a51_va_free(&p, 0x30000000, 0x10000);                     /* outside the pool: ignored */
}

int
main(void)
{
	test_pte_encoding();
	test_pt_index();
	test_va_lowest_first_reuse();
	test_va_whole_range();
	puts("all mmu tests passed");
	return 0;
}
