/* SPDX-License-Identifier: GPL-2.0-only
 * Galaxy A51 (Exynos 9611) UFS read-only probe, run by the shim before XNU.
 *
 * Adapted from shim/dreamlte/ufs_probe.c, which proved the Samsung Exynos UFS
 * quirks on the S8. Address map for this device, from the live /proc/iomem:
 *   13520000-135201ff : /ufs@0x13520000     UFSHCI standard registers
 *   13521100-135212ff : /ufs@0x13520000     Exynos vendor HCI block
 *   13524000-135247ff : /ufs@0x13520000/ufs-phy
 *   13530000-135300ff : /ufs@0x13520000     UFSP (protector), i.e. HCI+0x10000
 * Boot-1 measured CAP 0x1303ff0f (bit24 64AS set) and VERSION 0x0210.
 *
 * S-Boot read BOOT from this host, so the link is up and we reuse it: point the
 * transfer request list at our own memory and issue polled SCSI commands.
 * Only TEST UNIT READY, REQUEST SENSE, START STOP UNIT, READ(10) and
 * INQUIRY are issued. Nothing is ever written to the device.
 */
#include <stdint.h>
#include "ufs_probe.h"

#define HCI		0x13520000UL	/* UFSHCI standard registers */
#define VS_HCI		0x13521100UL	/* Exynos vendor HCI registers */
#define UFSP		0x13530000UL	/* UFS protector (FMP/SMU) */
#define PHY		0x13524000UL

#define CAP		0x00
#define VER		0x08
#define IS		0x20
#define IE		0x24
#define HCS		0x30
#define HCE		0x34
#define UTRLBA		0x50
#define UTRLBAU		0x54
#define UTRLDBR		0x58
#define UTRLRSR		0x60
#define TXPRDT_ENTRY	0x00
#define RXPRDT_ENTRY	0x04
#define UTRL_NEXUS	0x40
#define UFSPRSECURITY	0x10

#define TIMER_HZ	26000000UL

static inline uint32_t rd(uintptr_t a) { return *(volatile uint32_t *)a; }
static inline void wr(uintptr_t a, uint32_t v) { *(volatile uint32_t *)a = v; }

static uint64_t probe_ticks(void)
{
	uint64_t v;
	__asm__ volatile("isb; mrs %0, cntpct_el0" : "=r"(v));
	return v;
}

/* DMA layout (MMU off: Device memory, no cache maintenance needed). */
#define D_UTRL		0x0000
#define D_UCD		0x1000		/* cmd 512 | resp 512 | PRDT at +1024 */
#define D_DATA		0x4000		/* 64 KiB */
#define D_SIZE		0x14000

static uintptr_t dma;
static uint32_t prdt_stride = 16;
static uint8_t tag;
static uint8_t cmd_lun;		/* UPIU LUN of the next command */

static void bzero_dev(uintptr_t a, uint32_t n)
{
	for (uint32_t i = 0; i < n; i += 4)
		wr(a + i, 0);
}

static uint8_t b8(uintptr_t a)
{
	return *(volatile uint8_t *)a;
}

/* Sense data of the last response UPIU (fixed format, after the 2-byte length
 * at offset 30): length | key | ASC | ASCQ, plus the response's header word. */
static uint64_t last_sense(void)
{
	uintptr_t r = dma + D_UCD + 512;
	uint32_t len = (uint32_t)b8(r + 30) << 8 | b8(r + 31);
	return (uint64_t)len << 32 | (uint32_t)(b8(r + 32 + 2) & 0xf) << 16 |
	       (uint32_t)b8(r + 32 + 12) << 8 | b8(r + 32 + 13);
}

/* One SCSI command in slot 0; data from the device into D_DATA. */
static int scsi(const uint8_t *cdb, unsigned cdb_len, uint32_t len, uint32_t *ocs_out)
{
	uintptr_t utrd = dma + D_UTRL, ucd = dma + D_UCD;
	uint64_t ucd_pa = ucd, data_pa = dma + D_DATA;

	bzero_dev(utrd, 32);
	bzero_dev(ucd, 1024 + 16 * 128);
	/* COMMAND UPIU */
	*(volatile uint8_t *)(ucd + 0) = 0x01;
	*(volatile uint8_t *)(ucd + 1) = len ? 0x40 : 0x00;	/* R: data in */
	*(volatile uint8_t *)(ucd + 2) = cmd_lun;
	*(volatile uint8_t *)(ucd + 3) = ++tag;
	*(volatile uint8_t *)(ucd + 12) = (uint8_t)(len >> 24);
	*(volatile uint8_t *)(ucd + 13) = (uint8_t)(len >> 16);
	*(volatile uint8_t *)(ucd + 14) = (uint8_t)(len >> 8);
	*(volatile uint8_t *)(ucd + 15) = (uint8_t)len;
	for (unsigned i = 0; i < cdb_len; i++)
		*(volatile uint8_t *)(ucd + 16 + i) = cdb[i];

	uint32_t n = 0;
	for (uint32_t done = 0; done < len; done += 4096, n++) {
		uint32_t chunk = len - done < 4096 ? len - done : 4096;
		uintptr_t e = ucd + 1024 + n * prdt_stride;
		wr(e + 0, (uint32_t)(data_pa + done));
		wr(e + 4, (uint32_t)((data_pa + done) >> 32));
		wr(e + 12, chunk - 1);
	}
	/* CT=1 (UFS storage), DD=2 (device to memory) when reading, I=1. */
	wr(utrd + 0, (1u << 28) | ((len ? 2u : 0u) << 25) | (1u << 24));
	wr(utrd + 8, 0x0f);					/* OCS: invalid until done */
	wr(utrd + 16, (uint32_t)ucd_pa);
	wr(utrd + 20, (uint32_t)(ucd_pa >> 32));
	wr(utrd + 24, (512u << 16) | 512u);			/* resp offset | length, bytes */
	wr(utrd + 28, (1024u << 16) | (n * prdt_stride));	/* PRDT offset | length, bytes */
	__asm__ volatile("dsb sy" ::: "memory");

	wr(VS_HCI + UTRL_NEXUS, rd(VS_HCI + UTRL_NEXUS) | 1);	/* slot 0 = SCSI command */
	wr(HCI + UTRLDBR, 1);
	uint64_t end = probe_ticks() + TIMER_HZ * 2;
	while (rd(HCI + UTRLDBR) & 1) {
		if (probe_ticks() > end) {
			*ocs_out = 0xdead;
			return -1;
		}
	}
	wr(HCI + IS, rd(HCI + IS));
	uint32_t ocs = rd(utrd + 8) & 0xff;
	*ocs_out = ocs | (uint32_t)b8(ucd + 512) << 8 |
		   (uint32_t)b8(ucd + 512 + 6) << 16 |
		   (uint32_t)b8(ucd + 512 + 7) << 24;
	if (ocs || b8(ucd + 512) != 0x21 || b8(ucd + 512 + 6) || b8(ucd + 512 + 7))
		return -2;
	return 0;
}

static int read_blocks(uint32_t lba, uint32_t count, uint32_t *st)
{
	uint8_t cdb[10] = { 0x28, 0, (uint8_t)(lba >> 24), (uint8_t)(lba >> 16),
			    (uint8_t)(lba >> 8), (uint8_t)lba, 0, 0, (uint8_t)count, 0 };
	return scsi(cdb, 10, count * 4096, st);
}

/* GPT partition names are UTF-16LE; the A51's are lower case ("userdata"),
 * the S8's were upper case, so compare case-insensitively. */
static int name_is(uintptr_t e, const char *want)
{
	for (int c = 0; c < 36; c++) {
		uint16_t ch = (uint16_t)(b8(e + 56 + 2 * c) | b8(e + 57 + 2 * c) << 8);
		unsigned char a = (unsigned char)ch, b = (unsigned char)want[c];
		if (a >= 'A' && a <= 'Z')
			a += 'a' - 'A';
		if (b >= 'A' && b <= 'Z')
			b += 'a' - 'A';
		if (a != b)
			return 0;
		if (!ch)
			return 1;
	}
	return 0;
}

static uint64_t le64(uintptr_t a)
{
	uint64_t v = 0;
	for (int i = 7; i >= 0; i--)
		v = v << 8 | b8(a + i);
	return v;
}

static uint32_t le32(uintptr_t a)
{
	return (uint32_t)b8(a) | (uint32_t)b8(a + 1) << 8 |
	       (uint32_t)b8(a + 2) << 16 | (uint32_t)b8(a + 3) << 24;
}

static void hexdump(void (*out)(const char *), uintptr_t p, unsigned n)
{
	static const char hex[] = "0123456789abcdef";
	char line[64];
	for (unsigned i = 0; i < n; i += 16) {
		unsigned m = 0;
		line[m++] = ' ';
		line[m++] = ' ';
		for (unsigned j = 0; j < 16 && i + j < n; j++) {
			uint8_t b = b8(p + i + j);
			line[m++] = hex[b >> 4];
			line[m++] = hex[b & 0xf];
			line[m++] = ' ';
		}
		line[m] = 0;
		out(line);
		out("\n");
	}
}

/* LBAs measured from this unit's own GPT (see A51_PROGRESS.md). */
#define LBA_BOOT		0x6c90u
#define LBA_USERDATA		0x1f7500u

/* Self-check of the read path: the boot partition must start with the Android
 * boot magic and the kernel_size we flashed, and userdata's superblock tells us
 * which filesystem is there now. Read-only. */
static void probe_partitions(void (*kv)(const char *, uint64_t),
			     void (*out)(const char *))
{
	uint32_t st = 0;
	uintptr_t d = dma + D_DATA;

	if (read_blocks(LBA_BOOT, 1, &st)) {
		kv("READ boot rc", -1);
		kv("st", st);
		return;
	}
	out("  boot LBA 0x6c90 first 64 bytes:\n");
	hexdump(out, d, 64);
	{
		char sig[9];
		for (int i = 0; i < 8; i++)
			sig[i] = (char)b8(d + i);
		sig[8] = 0;
		out("  magic: ");
		out(sig);
		out("\n");
		kv("kernel_size", le32(d + 8));
		kv("page_size", le32(d + 36));
	}

	if (read_blocks(LBA_USERDATA, 1, &st)) {
		kv("READ userdata rc", -1);
		kv("st", st);
		return;
	}
	out("  userdata LBA 0x1f7500 first 64 bytes:\n");
	hexdump(out, d, 64);
	kv("f2fs_magic@1024", le32(d + 1024));
	kv("ext4_magic@1080", (uint64_t)(le32(d + 1080) & 0xffff));
	kv("hfs_sig@1024", (uint64_t)(le32(d + 1024) & 0xffff));
	out("  (f2fs=f2f52010, ext4=ef53, HFS+=482b/4858)\n");
}

void ufs_probe(void (*kv)(const char *, uint64_t), void (*out)(const char *),
	       uintptr_t dma_base)
{
	out("UFS probe (read-only, A51 0x13520000)\n");
	kv("CAP", rd(HCI + CAP));
	kv("VER", rd(HCI + VER));
	kv("HCS", rd(HCI + HCS));
	kv("HCE", rd(HCI + HCE));
	kv("UTRLBA_bootloader",
	   (uint64_t)rd(HCI + UTRLBAU) << 32 | rd(HCI + UTRLBA));
	kv("DBR", rd(HCI + UTRLDBR));
	kv("RSR", rd(HCI + UTRLRSR));
	kv("IS", rd(HCI + IS));
	kv("IE", rd(HCI + IE));
	kv("TXPRDT", rd(VS_HCI + TXPRDT_ENTRY));
	kv("RXPRDT", rd(VS_HCI + RXPRDT_ENTRY));
	kv("NEXUS", rd(VS_HCI + UTRL_NEXUS));
	kv("PHY_0", rd(PHY + 0x00));
	kv("PHY_4", rd(PHY + 0x04));
	uint32_t sec = rd(UFSP + UFSPRSECURITY);
	kv("UFSPRSEC", sec);
	prdt_stride = ((sec >> 19) & 3) == 3 ? 128 : 16;
	kv("prdt_stride", prdt_stride);
	kv("dma_base", dma_base);

	/* Exynos (UFSHCD_QUIRK_USE_OF_HCE): the standard HCE reads 0 while the
	 * host runs. Readiness is HCS bit0 (DP) + bit1 (UTRLRDY). */
	if ((rd(HCI + HCS) & 3) != 3) {
		out("UFS: host not ready, skipping commands\n");
		return;
	}
	if (rd(HCI + UTRLDBR)) {
		out("UFS: bootloader requests outstanding, skipping\n");
		return;
	}
	dma = dma_base;
	if ((dma_base >> 32) && !(rd(HCI + CAP) & (1u << 24))) {
		out("UFS: no 64-bit DMA, skipping\n");
		return;
	}
	bzero_dev(dma, D_SIZE);
	wr(HCI + IE, 0);
	wr(HCI + IS, rd(HCI + IS));
	wr(HCI + UTRLRSR, 0);
	wr(HCI + UTRLBA, (uint32_t)(dma + D_UTRL));
	wr(HCI + UTRLBAU, (uint32_t)((dma + D_UTRL) >> 32));
	wr(HCI + UTRLRSR, 1);
	kv("UTRLBA_ours", (uint64_t)rd(HCI + UTRLBAU) << 32 | rd(HCI + UTRLBA));
	kv("RSR_after", rd(HCI + UTRLRSR));
	if (rd(HCI + UTRLBA) != (uint32_t)(dma + D_UTRL) || !(rd(HCI + UTRLRSR) & 1)) {
		out("UFS: host did not take our list\n");
		return;
	}

	/* INQUIRY on LUN 0: vendor/product/rev, so we know which UFS part this
	 * unit has (it varies between A51 builds). */
	static const uint8_t inq[6] = { 0x12, 0, 0, 0, 36, 0 };
	uint32_t st = 0;
	int rc = scsi(inq, 6, 36, &st);
	kv("INQUIRY rc", (uint64_t)(int64_t)rc);
	kv("st", st);
	if (!rc) {
		uintptr_t q = dma + D_DATA;
		char s[20];
		for (int i = 0; i < 8; i++)			/* vendor, 8 bytes */
			s[i] = (char)b8(q + 8 + i);
		s[8] = 0;
		out("  vendor: ");
		out(s);
		for (int i = 0; i < 16; i++)			/* product, 16 bytes */
			s[i] = (char)b8(q + 16 + i);
		s[16] = 0;
		out(" product: ");
		out(s);
		for (int i = 0; i < 4; i++)			/* revision, 4 bytes */
			s[i] = (char)b8(q + 32 + i);
		s[4] = 0;
		out(" rev: ");
		out(s);
		out("\n");
	}

	static const uint8_t tur[6] = { 0 };
	rc = -1;
	for (int i = 0; i < 3 && rc; i++) {
		rc = scsi(tur, 6, 0, &st);
		kv("TUR rc", (uint64_t)(int64_t)rc);
		kv("st", st);
		kv("sense(len|key|asc|ascq)", last_sense());
	}

	static const uint8_t rs[6] = { 0x03, 0, 0, 0, 18, 0 };
	rc = scsi(rs, 6, 18, &st);
	kv("REQSENSE rc", (uint64_t)(int64_t)rc);
	{
		uintptr_t d = dma + D_DATA;
		kv("sense key", b8(d + 2) & 0xf);
		kv("asc", b8(d + 12));
		kv("ascq", b8(d + 13));
	}

	/* NOT READY / 04h means S-Boot left the LU stopped; wake it the way
	 * Linux ufshcd does: START=1 on LUN 0, then power condition ACTIVE on
	 * the UFS Device well-known LUN 0xD0. */
	static const uint8_t ssu_start[6] = { 0x1b, 0, 0, 0, 0x01, 0 };
	static const uint8_t ssu_active[6] = { 0x1b, 0, 0, 0, 0x10, 0 };
	for (int step = 0; step < 2; step++) {
		cmd_lun = step ? 0xd0 : 0;
		rc = scsi(step ? ssu_active : ssu_start, 6, 0, &st);
		kv(step ? "SSU wlun ACTIVE rc" : "SSU lun0 START rc",
		   (uint64_t)(int64_t)rc);
		kv("st", st);
		kv("sense", last_sense());
		cmd_lun = 0;
		rc = scsi(tur, 6, 0, &st);
		kv("TUR rc", (uint64_t)(int64_t)rc);
		if (!rc)
			break;
		scsi(rs, 6, 18, &st);
		uintptr_t d = dma + D_DATA;
		kv("sense key", b8(d + 2) & 0xf);
		kv("asc", b8(d + 12));
		kv("ascq", b8(d + 13));
	}

	/* READ CAPACITY(10) gives the LUN size in 4 KiB blocks. */
	static const uint8_t rc10[10] = { 0x25, 0, 0, 0, 0, 0, 0, 0, 0, 0 };
	rc = scsi(rc10, 10, 8, &st);
	kv("READCAP rc", (uint64_t)(int64_t)rc);
	if (!rc) {
		uintptr_t d = dma + D_DATA;
		uint32_t last = ((uint32_t)b8(d) << 24) | ((uint32_t)b8(d + 1) << 16) |
				((uint32_t)b8(d + 2) << 8) | b8(d + 3);
		uint32_t blksz = ((uint32_t)b8(d + 4) << 24) | ((uint32_t)b8(d + 5) << 16) |
				 ((uint32_t)b8(d + 6) << 8) | b8(d + 7);
		kv("last_lba", last);
		kv("block_size", blksz);
	}

	for (int attempt = 0; attempt < 2; attempt++) {
		rc = read_blocks(1, 1, &st);
		kv("READ lba1 rc", (uint64_t)(int64_t)rc);
		kv("st", st);
		kv("sense", last_sense());
		kv("stride", prdt_stride);
		if (!rc)
			break;
		prdt_stride = prdt_stride == 16 ? 128 : 16;	/* try the other layout */
	}
	if (rc) {
		out("UFS: cannot read the GPT header\n");
		return;
	}

	uintptr_t d = dma + D_DATA;
	char sig[9];
	for (int i = 0; i < 8; i++)
		sig[i] = (char)b8(d + i);
	sig[8] = 0;
	out("  GPT sig: ");
	out(sig);
	out("\n");
	uint64_t entries = le64(d + 72);
	uint64_t alt = le64(d + 32);
	uint32_t nent = (uint32_t)le64(d + 80);
	kv("entries_lba", entries);
	kv("alt_header_lba", alt);
	kv("n_entries", nent);
	if (nent > 128 || entries > 64)
		return;
	rc = read_blocks((uint32_t)entries, 4, &st);	/* 128 x 128 = 16 KiB */
	if (rc) {
		kv("READ entries rc", (uint64_t)(int64_t)rc);
		kv("st", st);
		return;
	}
	out("  partitions (name first last blocks):\n");
	for (uint32_t i = 0; i < nent; i++) {
		uintptr_t e = d + i * 128;
		if (!le64(e + 32) && !le64(e + 40))
			continue;			/* empty slot */
		char nm[37];
		int c;
		for (c = 0; c < 36 && b8(e + 56 + 2 * c); c++)
			nm[c] = (char)b8(e + 56 + 2 * c);
		nm[c] = 0;
		out("   ");
		out(nm);
		out(" ");
		kv("", le64(e + 32));
		kv("", le64(e + 40));
		kv("", le64(e + 40) - le64(e + 32) + 1);
		if (name_is(e, "userdata") || name_is(e, "boot") ||
		    name_is(e, "super"))
			out("    <== target\n");
	}
	probe_partitions(kv, out);
	out("UFS probe done\n");
}
