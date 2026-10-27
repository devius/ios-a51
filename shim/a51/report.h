/* SPDX-License-Identifier: GPL-2.0-only
 * Shared ASCII report sink: every stage of the A51 shim writes into one buffer
 * which is then published as a forged ramoops record (see emit_report).
 */
#ifndef A51_REPORT_H
#define A51_REPORT_H

#include <stdint.h>

void rputc(char c);
void rputs(const char *s);
void rhex64(uint64_t v);
void rhex32(uint32_t v);
void rdec(uint64_t v);
void rkv(const char *key, uint64_t value);
void rkv32(const char *key, uint32_t value);
void append_marker(const char *tag);
void emit_report(void);

/* Binary 24-slot record fields, mirrored into the sec_* log regions. */
void log_field(unsigned slot, uint64_t value);

#endif
