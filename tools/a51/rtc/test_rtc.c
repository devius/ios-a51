#include <stdint.h>
#include <stdio.h>
#include <assert.h>
#include "fns.c"
int main(void) {
	/* 2026-10-29 04:52:07 UTC, Thursday (one-hot bit 4), sec@04 layout */
	int a[8] = {7, 52, 4, 1 << 4, 29, 10, 26, 0};
	assert(a51_rtc_epoch(a) == 1793249527ull);
	/* msec@04 layout: msec byte first; the sec@04 reading must be rejected */
	int b[8] = {0x55, 7, 52, 4, 1 << 4, 29, 10, 26};
	assert(a51_rtc_epoch(&b[1]) == 1793249527ull && a51_rtc_epoch(&b[0]) == 0);
	assert(a51_rtc_epoch(&a[1]) == 0);                        /* and vice versa */
	int c[7] = {0, 0, 0, 1, 1, 1, 24};                        /* 2024-01-01 00:00:00 */
	assert(a51_rtc_epoch(c) == 1704067200ull);
	int d[7] = {0, 0, 0, 1, 29, 2, 28};                       /* leap day 2028 */
	assert(a51_rtc_epoch(d) == 1835395200ull);
	int bad[7] = {0, 0, 0, 3, 1, 1, 26};                      /* weekday not one-hot */
	assert(a51_rtc_epoch(bad) == 0);
	int old[7] = {0, 0, 0, 1, 1, 1, 0};                       /* year 2000: implausible */
	assert(a51_rtc_epoch(old) == 0);
	puts("rtc tests passed");
	return 0;
}
