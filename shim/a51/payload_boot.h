/* SPDX-License-Identifier: GPL-2.0-only */
#ifndef A51_PAYLOAD_BOOT_H
#define A51_PAYLOAD_BOOT_H

#include <stdint.h>

/* Non-zero when the ramdisk S-Boot advertised holds a SWEETXNU payload. */
int payload_present(uintptr_t fdt, uint64_t *rd_start_out);

/* Copies the payload into place and jumps to XNU. Returns non-zero only if it
 * could not, with the reason already written to the report. */
int payload_boot(uintptr_t fdt);

#endif
