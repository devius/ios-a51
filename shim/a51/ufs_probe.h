/* SPDX-License-Identifier: GPL-2.0-only */
#ifndef A51_UFS_PROBE_H
#define A51_UFS_PROBE_H

#include <stdint.h>

/* Read-only survey of the Exynos 9611 UFS host: registers, device identity,
 * wake-up sequence, GPT header and the partition table. dma_base must point at
 * 80 KiB of DRAM nothing else uses. */
void ufs_probe(void (*kv)(const char *, uint64_t), void (*out)(const char *),
	       uintptr_t dma_base);

#endif
