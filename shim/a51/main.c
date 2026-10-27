/* SPDX-License-Identifier: GPL-2.0-only
 * A51 boot-1 diagnostic payload. MMU off, EL1, single CPU.
 *
 * Evidence channels, in order of how likely they are to survive a warm reboot
 * into OrangeFox:
 *   1. sec_tsp_log   0x91244000 (256 KiB) -> /proc/tsp_msg in recovery
 *   2. log_pstore    0xF9D10000 (2 MiB)   -> /proc/last_kmsg, tail copy only
 *   3. sec_debug_next 0x91388000 (8 MiB)  -> /proc/debug_history (maybe)
 *   4. sec_avc_log   0x91202000 (256 KiB) -> binary record, needs /dev/mem
 *   5. sec_disp_log  0x91286000 (1 MiB)   -> binary record
 * Each region gets the ASCII report at its start and, where a driver is likely
 * to overwrite the start, a second copy near the end.
 *
 * The binary 24-slot record stays at the head of the four sec_* regions for
 * later tooling; the ASCII report is what we can actually read back today
 * because this recovery has no /dev/mem and no /proc/kcore.
 */
#include <stdint.h>
#include <stddef.h>
#include "ufs_probe.h"
#include "payload_boot.h"
#include "report.h"
#include "../fdt.h"

#define BIT(n)              (1U << (n))

#define LOG_AVC             0x91202000UL   /* sec_avc_log    256 KiB */
#define LOG_TSP             0x91244000UL   /* sec_tsp_log    256 KiB */
#define LOG_DISP            0x91286000UL   /* sec_disp_log     1 MiB */
#define LOG_DEBUG           0x91388000UL   /* sec_debug_next   8 MiB */
#define LOG_ESS             0xF9000000UL   /* ess_setup / debug_snapshot */
#define LOG_PSTORE          0xF9D10000UL   /* ramoops: attached 0x200000@0xf9d10000 */

#define DECON               0x148B0000UL
#define DSIM                0x148E0000UL
#define DPP0                0x14884000UL
#define GICD                0x12301000UL
#define UFS                 0x13520000UL
#define PMU                 0x11860000UL
#define FB_BASE             0xCA000000UL
#define FB_WIDTH            1080U
#define FB_HEIGHT           2400U
#define FB_STRIDE           (FB_WIDTH * 4U)

#define TIMER_HZ            26000000UL
/* Diagnostic build: a long, unmistakable hold so the time it takes the phone
 * to come back to recovery proves whether S-Boot ran us at all. */
#define LOOP_SECONDS        25U

#define GLOBAL_CONTROL              0x0000U
#define SHADOW_REG_UPDATE_REQ       0x0060U
#define HW_SW_TRIG_CONTROL          0x0070U
#define HW_SW_TRIG_TIMER            0x0074U
#define HW_TE_CNT                   0x0078U
#define INTERRUPT_PENDING           0x004CU
#define SW_TRIG_EN                  BIT(8)
#define HW_SW_TRIG_TIMER_EN         BIT(2)
#define HW_SW_TRIG_TIMER_CLEAR      BIT(3)
#define SHADOW_GLOBAL               BIT(31)

#define IDMA_ENABLE                 0x0000U
#define IDMA_SRC_SIZE               0x0010U
#define IDMA_IN_BASE_ADDR_Y         0x0040U

static inline uint32_t rd32(uintptr_t a) { return *(volatile uint32_t *)a; }
static inline void wr32(uintptr_t a, uint32_t v) { *(volatile uint32_t *)a = v; }
static inline uint64_t rd64(uintptr_t a) { return *(volatile uint64_t *)a; }
static inline void wr64(uintptr_t a, uint64_t v) { *(volatile uint64_t *)a = v; }

static uint64_t ticks(void)
{
    uint64_t v;
    __asm__ volatile("isb; mrs %0, cntpct_el0" : "=r"(v));
    return v;
}

static void dcache_clean(uintptr_t start, uintptr_t end)
{
    uint64_t ctr;
    __asm__ volatile("mrs %0, ctr_el0" : "=r"(ctr));
    uintptr_t line = 4UL << ((ctr >> 16) & 0xf);
    for (uintptr_t p = start & ~(line - 1); p < end; p += line)
        __asm__ volatile("dc cvac, %0" : : "r"(p) : "memory");
    __asm__ volatile("dsb sy" : : : "memory");
}

/* ------------------------------------------------------------------ report */

#define REPORT_MAX 24576
static char report[REPORT_MAX];
static unsigned report_len;

static void write_ramoops_dmesg(void);
static void write_ramoops_pmsg(void);

void rputc(char c)
{
    if (report_len + 1 < REPORT_MAX)
        report[report_len++] = c;
}

void rputs(const char *s)
{
    while (*s)
        rputc(*s++);
}

void rhex64(uint64_t v)
{
    rputs("0x");
    for (int shift = 60; shift >= 0; shift -= 4) {
        unsigned d = (unsigned)((v >> shift) & 0xf);
        rputc((char)(d < 10 ? '0' + d : 'a' + d - 10));
    }
}

void rhex32(uint32_t v) { rhex64(v); }

void rdec(uint64_t v)
{
    char tmp[24];
    int n = 0;
    if (!v) { rputc('0'); return; }
    while (v) { tmp[n++] = (char)('0' + (unsigned)(v % 10)); v /= 10; }
    while (n) rputc(tmp[--n]);
}

void rkv(const char *key, uint64_t value)
{
    rputs("  ");
    rputs(key);
    rputs(" = ");
    rhex64(value);
    rputc('\n');
}

void rkv32(const char *key, uint32_t value)
{
    rputs("  ");
    rputs(key);
    rputs(" = ");
    rhex32(value);
    rputc('\n');
}

/* Where the report is copied. Second copies sit far enough into the region
 * that a driver rewriting the head does not erase them. */
struct sink { uintptr_t base; uintptr_t off; };
static const struct sink sinks[] = {
    { LOG_TSP,    0x00000 },
    { LOG_TSP,    0x30000 },
    { LOG_DISP,   0x00000 },
    { LOG_DISP,   0xf0000 },
    { LOG_AVC,    0x30000 },
    { LOG_DEBUG,  0x00000 },
    { LOG_DEBUG,  0x700000 },
    { LOG_PSTORE, 0x1f0000 },
};

void emit_report(void)
{
    report[report_len] = 0;
    for (unsigned i = 0; i < sizeof(sinks) / sizeof(sinks[0]); ++i) {
        uintptr_t dst = sinks[i].base + sinks[i].off;
        volatile char *d = (volatile char *)dst;
        for (unsigned j = 0; j < report_len; ++j)
            d[j] = report[j];
        dcache_clean(dst, dst + report_len + 64);
    }
    write_ramoops_dmesg();
    write_ramoops_pmsg();
}

void append_marker(const char *tag)
{
    rputs("\n=== A51SHIM6 ");
    rputs(tag);
    rputs(" ===\n");
}

/* ------------------------------------------------------- DPU20 bus survey
 * iomem shows every dpp@0x1488N000 node with TWO register windows, e.g.
 *   14881000-14881fff : /dpp@0x14881000      14891000-14891fff : /dpp@0x14881000
 *   14884000-14884fff : /dpp@0x14884000      14895000-14895fff : /dpp@0x14884000
 * The first probe only read the primary window of dpp0 and got zeros, so the
 * IDMA block that actually scans 0xca000000 must be found by surveying both
 * windows of all four DPPs plus the DECON window/blender registers. Whichever
 * IN_BASE_ADDR_Y equals the framebuffer PA is the channel XNU will flip.
 */
static void probe_dpu(void)
{
    static const uintptr_t dpp[8] = {
        0x14881000UL, 0x14891000UL,
        0x14882000UL, 0x14892000UL,
        0x14883000UL, 0x14896000UL,
        0x14884000UL, 0x14895000UL,
    };
    rputs("\nDPU survey (IDMA regs per regs-dpp.h):\n");
    for (unsigned i = 0; i < 8; ++i) {
        uintptr_t b = dpp[i];
        uint32_t en  = rd32(b + 0x00);
        uint32_t con = rd32(b + 0x08);
        uint32_t src = rd32(b + 0x10);
        uint32_t off = rd32(b + 0x14);
        uint32_t img = rd32(b + 0x18);
        uint32_t y   = rd32(b + 0x40);
        rputs("  dpp@");
        rhex32((uint32_t)b);
        rputs(" en=");
        rhex32(en);
        rputs(" incon=");
        rhex32(con);
        rputs(" src=");
        rhex32(src);
        rputs(" off=");
        rhex32(off);
        rputs(" img=");
        rhex32(img);
        rputs(" Y=");
        rhex32(y);
        if (y == (uint32_t)FB_BASE)
            rputs("   <== SCANS FRAMEBUFFER");
        rputc('\n');
    }

    rputs("\nDECON windows (WIN_CONTROL_0 = 0x1000 + w*0x30):\n");
    for (unsigned w = 0; w < 6; ++w) {
        uint32_t c0 = rd32(DECON + 0x1000 + w * 0x30);
        uint32_t c1 = rd32(DECON + 0x1004 + w * 0x30);
        if (!c0 && !c1)
            continue;
        rputs("  win");
        rdec(w);
        rputs(" ctl0=");
        rhex32(c0);
        rputs(" ctl1=");
        rhex32(c1);
        rputc('\n');
    }

    rputs("\nDECON core:\n");
    rkv32("INTERRUPT_ENABLE@0x40", rd32(DECON + 0x40));
    rkv32("INTERRUPT_PENDING@0x4c", rd32(DECON + INTERRUPT_PENDING));
    rkv32("SRAM_SHARE_ENABLE@0x30", rd32(DECON + 0x30));
    rkv32("SCALED_SIZE_CONTROL_0@0xa0", rd32(DECON + 0xa0));
    rkv32("CLOCK_CONTROL_0@0xf0", rd32(DECON + 0xf0));
    rkv32("DSIM@148e0000+0x00", rd32(DSIM + 0x00));
    rkv32("DSIM@148e0000+0x08", rd32(DSIM + 0x08));
    rkv32("DSIM@148e0000+0x18", rd32(DSIM + 0x18));
    rkv32("DSIM@148e0000+0x20", rd32(DSIM + 0x20));
    /* disp_ss sysreg: PSR mode / trigger configuration lives here on DPU20. */
    rkv32("SYSREG_DISP@14810000+0x00", rd32(0x14810000UL));
    rkv32("SYSREG_DISP@14810000+0x04", rd32(0x14810004UL));
    rkv32("UFS@13520000+0x00 CAP", rd32(UFS + 0x00));
    rkv32("UFS@13520000+0x08 VER", rd32(UFS + 0x08));
    rkv32("GICD_CTLR@12301000", rd32(GICD + 0x0000));
    rkv32("GICC_IIDR@12302000+0xfc", rd32(0x12302000UL + 0xfc));
}

/* ------------------------------------------------------------------ font */

struct glyph { char ch; uint8_t rows[7]; };
static const struct glyph font[] = {
    {' ',{0,0,0,0,0,0,0}}, {'-',{0,0,0,31,0,0,0}},
    {':',{0,4,4,0,4,4,0}}, {'?',{14,17,1,2,4,0,4}},
    {'.',{0,0,0,0,0,0,4}}, {'/',{1,2,2,4,8,8,16}},
    {'0',{14,17,19,21,25,17,14}}, {'1',{4,12,4,4,4,4,14}},
    {'2',{14,17,1,2,4,8,31}}, {'3',{30,1,1,14,1,1,30}},
    {'4',{2,6,10,18,31,2,2}}, {'5',{31,16,30,1,1,17,14}},
    {'6',{6,8,16,30,17,17,14}}, {'7',{31,1,2,4,8,8,8}},
    {'8',{14,17,17,14,17,17,14}}, {'9',{14,17,17,15,1,2,12}},
    {'A',{14,17,17,31,17,17,17}}, {'B',{30,17,17,30,17,17,30}},
    {'C',{14,17,16,16,16,17,14}}, {'D',{30,17,17,17,17,17,30}},
    {'E',{31,16,16,30,16,16,31}}, {'F',{31,16,16,30,16,16,16}},
    {'G',{14,17,16,23,17,17,14}}, {'H',{17,17,17,31,17,17,17}},
    {'I',{14,4,4,4,4,4,14}}, {'J',{7,2,2,2,18,18,12}},
    {'K',{17,18,20,24,20,18,17}}, {'L',{16,16,16,16,16,16,31}},
    {'M',{17,27,21,21,17,17,17}}, {'N',{17,25,21,19,17,17,17}},
    {'O',{14,17,17,17,17,17,14}}, {'P',{30,17,17,30,16,16,16}},
    {'Q',{14,17,17,17,21,18,13}}, {'R',{30,17,17,30,20,18,17}},
    {'S',{15,16,16,14,1,1,30}}, {'T',{31,4,4,4,4,4,4}},
    {'U',{17,17,17,17,17,17,14}}, {'V',{17,17,17,17,17,10,4}},
    {'W',{17,17,17,21,21,21,10}}, {'X',{17,17,10,4,10,17,17}},
    {'Y',{17,17,10,4,4,4,4}}, {'Z',{31,1,2,4,8,16,31}},
};

static const uint8_t *glyph_for(char ch)
{
    if (ch >= 'a' && ch <= 'z')
        ch -= 'a' - 'A';
    for (unsigned i = 0; i < sizeof(font) / sizeof(font[0]); ++i)
        if (font[i].ch == ch)
            return font[i].rows;
    return font[3].rows;
}

/* ---------------------------------------------------------------- dashboard
 * The panel is the only evidence a human can read without a host, so it is used
 * as an instrument: the whole 16-bit RGB565 palette (65536 cells) proves that
 * every framebuffer address is written and scanned out, the gray ramp and Bayer
 * halftones prove the gamma/blend path, the R/G/B blocks prove the channel
 * order, and the counters prove the shim is still alive and that DECON keeps
 * latching. Layout is fixed so two runs can be compared pixel by pixel.
 */
struct board_info {
    uint64_t current_el, sctlr, mpidr, mmfr0, pfr0, cntfrq, fdt, image_pa;
    uint32_t gicd_typer, ufs_cap, ufs_ver, decon_ctl, decon_trig, decon_te,
             dpp_y;
};

#define MARGIN          24U
#define PALETTE_X       28U
#define PALETTE_Y       452U
#define PALETTE_CELL    4U          /* 256*4 = 1024 px wide and tall */

#define FB ((volatile uint32_t *)(uintptr_t)FB_BASE)

static void fb_rect(unsigned x, unsigned y, unsigned w, unsigned h, uint32_t c)
{
    for (unsigned j = 0; j < h; ++j) {
        if (y + j >= FB_HEIGHT)
            break;
        volatile uint32_t *row = FB + (size_t)(y + j) * FB_WIDTH;
        for (unsigned i = 0; i < w; ++i) {
            if (x + i >= FB_WIDTH)
                break;
            row[x + i] = c;
        }
    }
}

static void draw_text_at(unsigned x, unsigned y, unsigned scale,
                         const char *s, uint32_t fg)
{
    for (unsigned col = 0; s[col] && col < 58; ++col) {
        const uint8_t *g = glyph_for(s[col]);
        unsigned cx = x + col * 6 * scale;
        if (cx + 5 * scale > FB_WIDTH)
            break;
        for (unsigned gy = 0; gy < 7; ++gy)
            for (unsigned gx = 0; gx < 5; ++gx) {
                if (!(g[gy] & (1U << (4 - gx))))
                    continue;
                fb_rect(cx + gx * scale, y + gy * scale, scale, scale, fg);
            }
    }
}

static unsigned fmt_u(char *buf, uint64_t v)
{
    char tmp[24];
    unsigned n = 0;
    if (!v)
        tmp[n++] = '0';
    while (v) {
        tmp[n++] = (char)('0' + (unsigned)(v % 10));
        v /= 10;
    }
    for (unsigned i = 0; i < n; ++i)
        buf[i] = tmp[n - 1 - i];
    buf[n] = 0;
    return n;
}

static void draw_dec_at(unsigned x, unsigned y, unsigned scale, uint64_t v,
                        uint32_t fg)
{
    char buf[24];
    fmt_u(buf, v);
    draw_text_at(x, y, scale, buf, fg);
}

static void draw_hex_at(unsigned x, unsigned y, unsigned scale,
                        const char *label, uint64_t value, uint32_t fg)
{
    char line[44];
    unsigned n = 0;
    while (label[n] && n < 22) {
        line[n] = label[n];
        n++;
    }
    line[n++] = '0';
    line[n++] = 'X';
    for (int shift = 28; shift >= 0; shift -= 4) {
        unsigned d = (unsigned)((value >> shift) & 0xf);
        line[n++] = (char)(d < 10 ? '0' + d : 'A' + d - 10);
    }
    line[n] = 0;
    draw_text_at(x, y, scale, line, fg);
}

/* RGB565 -> XRGB8888, so the mosaic is a true 16-bit palette render. */
static uint32_t rgb565(unsigned c)
{
    unsigned r = (c >> 11) & 0x1f;
    unsigned g = (c >> 5) & 0x3f;
    unsigned b = c & 0x1f;
    r = (r * 255 + 15) / 31;
    g = (g * 255 + 31) / 63;
    b = (b * 255 + 15) / 31;
    return 0xff000000U | (r << 16) | (g << 8) | b;
}

static void paint_palette(void)
{
    for (unsigned row = 0; row < 256; ++row) {
        for (unsigned col = 0; col < 256; ++col) {
            uint32_t c = rgb565((row << 8) | col);
            fb_rect(PALETTE_X + col * PALETTE_CELL,
                    PALETTE_Y + row * PALETTE_CELL,
                    PALETTE_CELL, PALETTE_CELL, c);
        }
    }
}

static void paint_grays(unsigned y)
{
    /* 16 steps: the "16 shades" ramp, then a continuous 256-step gradient. */
    for (unsigned i = 0; i < 16; ++i) {
        unsigned v = (i * 255) / 15;
        fb_rect(MARGIN + i * 64, y, 60, 60, 0xff000000U | (v << 16) | (v << 8) | v);
    }
    for (unsigned x = 0; x < 1024; ++x) {
        unsigned v = (x * 255) / 1023;
        fb_rect(MARGIN + x, y + 72, 1, 48, 0xff000000U | (v << 16) | (v << 8) | v);
    }
}

static const uint8_t bayer4[4][4] = {
    { 0,  8,  2, 10 },
    { 12, 4, 14,  6 },
    { 3, 11,  1,  9 },
    { 15, 7, 13,  5 },
};

static void paint_halftone(unsigned y)
{
    /* Eight ordered-dither halftones from black to white. */
    for (unsigned p = 0; p < 8; ++p) {
        unsigned gray = (p * 255) / 7;
        unsigned x0 = MARGIN + p * 128;
        for (unsigned j = 0; j < 96; ++j) {
            for (unsigned i = 0; i < 120; ++i) {
                unsigned t = (bayer4[j & 3][i & 3] * 255 + 8) / 16;
                uint32_t c = (gray > t) ? 0xffffffffU : 0xff000000U;
                FB[(size_t)(y + j) * FB_WIDTH + x0 + i] = c;
            }
        }
    }
}

static void paint_order(unsigned y)
{
    static const uint32_t cols[6] = {
        0xffff0000U, 0xff00ff00U, 0xff0000ffU,
        0xffffff00U, 0xffffffffU, 0xff000000U,
    };
    static const char names[] = "RGBYWK";
    for (unsigned i = 0; i < 6; ++i) {
        unsigned x0 = MARGIN + i * 172;
        char label[2] = { names[i], 0 };
        fb_rect(x0, y, 160, 96, cols[i]);
        draw_text_at(x0 + 60, y + 38, 3, label,
                     (i == 4 || i == 3) ? 0xff000000U : 0xffffffffU);
    }
}

static void paint_dashboard(const struct board_info *bi)
{
    fb_rect(0, 0, FB_WIDTH, FB_HEIGHT, 0xff000000U);

    draw_text_at(MARGIN, 20, 3, "HACKIOS SHIM A51 REV8 OK", 0xffffffffU);
    draw_text_at(MARGIN, 76, 2,
                 "EXYNOS 9611 SM-A515F  FB 0XCA000000 1080X2400 XRGB8888",
                 0xff80ffffU);

    unsigned y = 112;
    const unsigned pitch = 22;
    draw_hex_at(MARGIN, y, 2, "CURRENT EL   ", bi->current_el, 0xffffff00U);
    draw_hex_at(MARGIN + 540, y, 2, "SCTLR ", bi->sctlr, 0xffffff00U);
    y += pitch;
    draw_hex_at(MARGIN, y, 2, "MPIDR        ", bi->mpidr, 0xffffff00U);
    draw_hex_at(MARGIN + 540, y, 2, "MMFR0 ", bi->mmfr0, 0xffffff00U);
    y += pitch;
    draw_hex_at(MARGIN, y, 2, "PFR0         ", bi->pfr0, 0xffffff00U);
    draw_hex_at(MARGIN + 540, y, 2, "CNTFRQ", bi->cntfrq, 0xffffff00U);
    y += pitch;
    draw_hex_at(MARGIN, y, 2, "FDT PA       ", bi->fdt, 0xff80ff80U);
    draw_hex_at(MARGIN + 540, y, 2, "IMG PA", bi->image_pa, 0xff80ff80U);
    y += pitch;
    draw_hex_at(MARGIN, y, 2, "GICD TYPER   ", bi->gicd_typer, 0xffff80ffU);
    draw_hex_at(MARGIN + 540, y, 2, "GICD CTLR", 0, 0xffff80ffU);
    y += pitch;
    draw_hex_at(MARGIN, y, 2, "UFS CAP      ", bi->ufs_cap, 0xffff80ffU);
    draw_hex_at(MARGIN + 540, y, 2, "UFS VER", bi->ufs_ver, 0xffff80ffU);
    y += pitch;
    draw_hex_at(MARGIN, y, 2, "DECON CTL    ", bi->decon_ctl, 0xff80ffffU);
    draw_hex_at(MARGIN + 540, y, 2, "TRIG", bi->decon_trig, 0xff80ffffU);
    y += pitch;
    draw_hex_at(MARGIN, y, 2, "TE CNT       ", bi->decon_te, 0xff80ffffU);
    draw_hex_at(MARGIN + 540, y, 2, "DPP Y", bi->dpp_y, 0xff80ffffU);

    y += pitch + 12;
    draw_text_at(MARGIN, y, 2, "RGB565 PALETTE 65536 COLOURS  ROW=HIGH BYTE COL=LOW BYTE",
                 0xffffffffU);
    paint_palette();

    y = PALETTE_Y + 256 * PALETTE_CELL + 14;
    draw_text_at(MARGIN, y, 2, "16 SHADES / CONTINUOUS GRADIENT", 0xffffffffU);
    paint_grays(y + 22);

    y += 22 + 72 + 48 + 20;
    draw_text_at(MARGIN, y, 2, "BAYER 4X4 HALFTONES", 0xffffffffU);
    paint_halftone(y + 22);

    y += 22 + 96 + 20;
    draw_text_at(MARGIN, y, 2, "CHANNEL ORDER CHECK", 0xffffffffU);
    paint_order(y + 22);

    draw_text_at(MARGIN, 2340, 2,
                 "LOG: FORGED RAMOOPS RECORD AT 0XF9D10000 -> /SYS/FS/PSTORE/DMESG-RAMOOPS-0",
                 0xff808080U);
}

static void update_counters(uint64_t ms, uint64_t loops, uint64_t frames,
                            uint32_t te, unsigned stage)
{
    const unsigned y = 2240;
    fb_rect(MARGIN, y - 4, FB_WIDTH - 2 * MARGIN, 96, 0xff000000U);
    draw_text_at(MARGIN, y, 2, "T=", 0xff00ff00U);
    draw_dec_at(MARGIN + 24, y, 2, ms / 1000, 0xff00ff00U);
    draw_text_at(MARGIN + 96, y, 2, ".", 0xff00ff00U);
    draw_dec_at(MARGIN + 108, y, 2, (ms / 100) % 10, 0xff00ff00U);
    draw_text_at(MARGIN + 132, y, 2, "S", 0xff00ff00U);
    draw_text_at(MARGIN + 168, y, 2, "LOOPS=", 0xff00ff00U);
    draw_dec_at(MARGIN + 240, y, 2, loops, 0xff00ff00U);
    draw_text_at(MARGIN + 420, y, 2, "FRAMES=", 0xffffff00U);
    draw_dec_at(MARGIN + 504, y, 2, frames, 0xffffff00U);
    draw_text_at(MARGIN + 660, y, 2, "TE=", 0xffffff00U);
    draw_dec_at(MARGIN + 696, y, 2, te, 0xffffff00U);
    draw_text_at(MARGIN, y + 26, 2, "STAGE=", 0xff80ffffU);
    draw_dec_at(MARGIN + 72, y + 26, 2, stage, 0xff80ffffU);
    draw_text_at(MARGIN + 120, y + 26, 2, "HOLD 15S THEN PMU SWRESET TO RECOVERY",
                 0xff80ffffU);
}


/* ------------------------------------------------------------------ RTC
 * This recovery has no /dev/mem (ENXIO) and no /proc/kcore, so the RAM log
 * regions cannot be read back. The Exynos RTC at 0x11a20000 is plain MMIO,
 * survives a warm reset, and recovery prints it verbatim through
 * /proc/driver/rtc -- which makes it a 12-digit telemetry channel:
 *   time  41-11-11 11:11:11  <- unmistakable "the A51 shim ran" marker
 *   alarm stage / run / loops(k) / DECON GLOBAL_CONTROL / TRIG>>8 / FB>>28
 * Access widths follow drivers/rtc/rtc-s3c.c: readb/writeb for everything
 * except YEAR, which is readw/writew.
 */
#define RTC_BASE            0x11A20000UL
#define RTC_ALMSEC          0x54U
#define RTC_ALMMIN          0x58U
#define RTC_ALMHOUR         0x5cU
#define RTC_ALMDATE         0x60U
#define RTC_ALMMON          0x64U
#define RTC_ALMYEAR         0x68U
#define RTC_RTCCON          0x40U
#define RTC_SEC             0x70U
#define RTC_MIN             0x74U
#define RTC_HOUR            0x78U
#define RTC_DATE            0x7cU
#define RTC_MON             0x84U
#define RTC_YEAR            0x88U
#define RTC_RTCCON_RTCEN    0x1U

static inline uint8_t rtc_r8(uint32_t off)
{
    return *(volatile uint8_t *)(RTC_BASE + off);
}
static inline uint16_t rtc_r16(uint32_t off)
{
    return *(volatile uint16_t *)(RTC_BASE + off);
}
static inline void rtc_w8(uint32_t off, uint8_t v)
{
    *(volatile uint8_t *)(RTC_BASE + off) = v;
}
static inline void rtc_w16(uint32_t off, uint16_t v)
{
    *(volatile uint16_t *)(RTC_BASE + off) = v;
}

static uint8_t bin2bcd(unsigned v)
{
    v %= 100;
    return (uint8_t)(((v / 10) << 4) | (v % 10));
}

struct rtc_snapshot { uint16_t con, year; uint8_t mon, date, hour, min, sec; };

static void rtc_read(struct rtc_snapshot *s)
{
    s->sec  = rtc_r8(RTC_SEC);
    s->min  = rtc_r8(RTC_MIN);
    s->hour = rtc_r8(RTC_HOUR);
    s->date = rtc_r8(RTC_DATE);
    s->mon  = rtc_r8(RTC_MON);
    s->year = rtc_r16(RTC_YEAR);
    s->con  = rtc_r16(RTC_RTCCON);
}

static void rtc_report(const char *tag, const struct rtc_snapshot *s)
{
    rputs("  rtc ");
    rputs(tag);
    rputs(" con=");
    rhex32(s->con);
    rputs(" y=");
    rhex32(s->year);
    rputs(" mo=");
    rhex32(s->mon);
    rputs(" d=");
    rhex32(s->date);
    rputs(" h=");
    rhex32(s->hour);
    rputs(" mi=");
    rhex32(s->min);
    rputs(" s=");
    rhex32(s->sec);
    rputc('\n');
}

static void rtc_write_telemetry(unsigned stage, unsigned run, uint64_t loops,
                                uint32_t decon_ctl, uint32_t trig,
                                uint32_t fb_high_nibble)
{
    uint16_t con = rtc_r16(RTC_RTCCON);
    rtc_w16(RTC_RTCCON, (uint16_t)(con | RTC_RTCCON_RTCEN));

    rtc_w8(RTC_SEC,  bin2bcd(11));
    rtc_w8(RTC_MIN,  bin2bcd(11));
    rtc_w8(RTC_HOUR, bin2bcd(11));
    rtc_w8(RTC_DATE, bin2bcd(11));
    rtc_w8(RTC_MON,  bin2bcd(11));
    rtc_w16(RTC_YEAR, bin2bcd(41));        /* "A51" marker */

    rtc_w8(RTC_ALMSEC,  bin2bcd(stage));
    rtc_w8(RTC_ALMMIN,  bin2bcd(run));
    rtc_w8(RTC_ALMHOUR, bin2bcd((unsigned)(loops / 1000U)));
    rtc_w8(RTC_ALMDATE, bin2bcd(decon_ctl & 0x3fU));
    rtc_w8(RTC_ALMMON,  bin2bcd((trig >> 8) & 0xffU));
    rtc_w16(RTC_ALMYEAR, bin2bcd(fb_high_nibble));

    __asm__ volatile("dsb sy" : : : "memory");
    rtc_w16(RTC_RTCCON, con);
    __asm__ volatile("dsb sy" : : : "memory");
}

/* ------------------------------------------------- forged ramoops records
 * This recovery exposes no /dev/mem and no /proc/kcore, so raw writes into the
 * sec_* log regions cannot be read back. The one RAM region recovery *does*
 * publish is the pstore/ramoops area: lib/debug-snapshot-pstore.c sizes it as
 * record=console=ftrace=pmsg=SZ_512K inside log_pstore (0xf9d10000, 2 MiB), and
 * fs/pstore/ram.c lays the zones out in that order:
 *   dump0   0xf9d10000   console 0xf9d90000
 *   ftrace  0xf9e10000   pmsg    0xf9e90000
 * Each zone starts with struct persistent_ram_buffer {u32 sig; s32 start;
 * s32 size; u8 data[]} and sig = 0x43474244 ("DBGC"). ecc is 0/0, so no parity
 * bytes are needed. A DMESG record additionally needs the ASCII header
 * "====<sec>.<nsec>-D\n" or ramoops_pstore_read() zaps it; PMSG is raw.
 * Result: /sys/fs/pstore/dmesg-ramoops-0 and pmsg-ramoops-0 carry our report.
 */
#define RAMOOPS_SIG       0x43474244U
#define RAMOOPS_BASE      0xF9D10000UL
#define RAMOOPS_DUMP      (RAMOOPS_BASE + 0x000000UL)
#define RAMOOPS_CONSOLE   (RAMOOPS_BASE + 0x080000UL)
#define RAMOOPS_FTRACE    (RAMOOPS_BASE + 0x100000UL)
#define RAMOOPS_PMSG      (RAMOOPS_BASE + 0x180000UL)
#define RAMOOPS_HDR_SIZE  12U

static volatile uint8_t *prz_data(uintptr_t zone)
{
    return (volatile uint8_t *)(zone + RAMOOPS_HDR_SIZE);
}

static void prz_seal(uintptr_t zone, uint32_t size)
{
    volatile uint32_t *h = (volatile uint32_t *)zone;
    h[0] = RAMOOPS_SIG;
    h[1] = 0;          /* start */
    h[2] = size;       /* size  */
    __asm__ volatile("dsb sy" : : : "memory");
    dcache_clean(zone, zone + RAMOOPS_HDR_SIZE + size + 64);
}

/* "====1700000000.000000000-D\n" - a fixed, obviously synthetic timestamp. */
static const char kmsg_hdr[] = "====1700000000.000000000-D\n";

static void write_ramoops_dmesg(void)
{
    /* volatile: keep GCC from materialising the zone address through an
     * absolute literal pool entry (the image must stay relocation-free). */
    volatile uintptr_t zone = RAMOOPS_DUMP;
    volatile uint8_t *d = prz_data(zone);
    uint32_t n = 0;
    for (const char *p = kmsg_hdr; *p; ++p)
        d[n++] = (uint8_t)*p;
    for (uint32_t i = 0; i < report_len; ++i)
        d[n++] = (uint8_t)report[i];
    d[n] = 0;
    prz_seal(zone, n);
}

static void write_ramoops_pmsg(void)
{
    volatile uintptr_t zone = RAMOOPS_PMSG;
    volatile uint8_t *d = prz_data(zone);
    for (uint32_t i = 0; i < report_len; ++i)
        d[i] = (uint8_t)report[i];
    d[report_len] = 0;
    prz_seal(zone, report_len + 1);
}

/* Adapters so the S8-style probe can write straight into our report. */
static void rep_out(const char *s)
{
    rputs(s);
}

static void rep_kv(const char *key, uint64_t value)
{
    rputs("  ");
    rputs(key);
    if (*key)
        rputs(" = ");
    else
        rputc(' ');
    rhex64(value);
    rputc('\n');
}

/* Bank 1 is free at this point (S-Boot uses bank 0 for the image, the FDT and
 * the ramdisk), so the probe's 80 KiB of DMA buffers go there. CAP bit 24 says
 * the host supports 64-bit addressing. */
#define UFS_DMA_BASE 0x880000000UL

/* ------------------------------------------------------------------ record */

static void log_write(uintptr_t base, const uint64_t *rec, unsigned words)
{
    for (unsigned i = 0; i < words; ++i)
        wr64(base + i * 8U, rec[i]);
    dcache_clean(base, base + words * 8U);
}

void log_field(unsigned slot, uint64_t value)
{
    static const uintptr_t bases[] = { LOG_AVC, LOG_TSP, LOG_DISP, LOG_DEBUG };
    for (unsigned i = 0; i < 4; ++i) {
        wr64(bases[i] + slot * 8U, value);
        dcache_clean(bases[i], bases[i] + 24 * 8U);
    }
}

static void psci_reset(void)
{
    register uint64_t x0 __asm__("x0") = 0x84000009UL;
    __asm__ volatile("smc #0" : "+r"(x0) : : "x1", "x2", "x3", "memory");
}

/* INFORM2/3 recovery magic + EXYNOS_SWRESET (exynos-regs-pmu.h: INFORM0 0x800,
 * SWRESET 0x400, SPARE2/3 0x908/0x90c) on the 9610 PMU at 0x11860000. */
static void recovery_reset(void)
{
    wr32(PMU + 0x808, 0x12345678U);
    wr32(PMU + 0x80c, 0x12345674U);
    wr32(PMU + 0x908, 0x12345678U);
    wr32(PMU + 0x90c, 0x12345674U);
    __asm__ volatile("dsb sy" : : : "memory");
    wr32(PMU + 0x400, 1);
    __asm__ volatile("dsb sy" : : : "memory");
}

void a51_main(uintptr_t fdt, uint64_t current_el, uintptr_t image_pa)
{
    /* Very first thing: prove we were entered, before any peripheral read can
     * fault. Alarm second = 8 means "reached main". */
    rtc_write_telemetry(8, 0, 0, 0, 0, 0);

    uint64_t cntfrq;
    __asm__ volatile("isb; mrs %0, cntfrq_el0" : "=r"(cntfrq));
    if (!cntfrq) {
        cntfrq = TIMER_HZ;
        __asm__ volatile("msr cntfrq_el0, %0" : : "r"(cntfrq));
    }

    uint64_t rec[24];
    for (unsigned i = 0; i < 24; ++i)
        rec[i] = 0;

    uint64_t mpidr, sctlr, mmfr0, pfr0;
    __asm__ volatile("mrs %0, mpidr_el1" : "=r"(mpidr));
    __asm__ volatile("mrs %0, sctlr_el1" : "=r"(sctlr));
    __asm__ volatile("mrs %0, id_aa64mmfr0_el1" : "=r"(mmfr0));
    __asm__ volatile("mrs %0, id_aa64pfr0_el1" : "=r"(pfr0));

    uint32_t gicd_typer  = rd32(GICD + 0x0004);
    uint32_t ufs_ver     = rd32(UFS + 0x0008);
    uint32_t decon_ctl   = rd32(DECON + GLOBAL_CONTROL);
    uint32_t decon_shadow = rd32(DECON + SHADOW_REG_UPDATE_REQ);
    uint32_t decon_trig  = rd32(DECON + HW_SW_TRIG_CONTROL);
    uint32_t decon_te    = rd32(DECON + HW_TE_CNT);
    uint32_t dsim_status = rd32(DSIM + 0x0004);
    uint32_t dpp0_base   = rd32(DPP0 + IDMA_IN_BASE_ADDR_Y);
    uint32_t dpp0_src    = rd32(DPP0 + IDMA_SRC_SIZE);
    uint32_t dpp0_en     = rd32(DPP0 + IDMA_ENABLE);

    uint64_t previous = rd64(LOG_AVC);
    uint64_t runs = (previous == 0x314d494853313541ULL) ? rd64(LOG_AVC + 23 * 8U) + 1 : 1;

    rec[0]  = 0x314d494853313541ULL;      /* "A51SHIM1" */
    rec[1]  = current_el;
    rec[2]  = sctlr;
    rec[3]  = fdt;
    rec[4]  = image_pa;
    rec[5]  = mpidr;
    rec[6]  = cntfrq;
    rec[7]  = ticks();
    rec[8]  = mmfr0;
    rec[9]  = gicd_typer;
    rec[10] = ufs_ver;
    rec[11] = decon_ctl;
    rec[12] = decon_shadow;
    rec[13] = decon_trig;
    rec[14] = decon_te;
    rec[15] = dsim_status;
    rec[16] = dpp0_base;
    rec[17] = dpp0_src;
    rec[18] = dpp0_en;
    rec[19] = FB_BASE;
    rec[20] = 1;
    rec[23] = runs;
    log_write(LOG_AVC, rec, 24);
    log_write(LOG_DISP, rec, 24);
    log_write(LOG_DEBUG, rec, 24);
    /* LOG_ESS (0xf9000000, debug_snapshot) is deliberately not written until
     * we have proof the shim runs: it may be TrustZone-owned and a write to it
     * could take an external abort with no vector table installed. */

    /* ASCII report: readable through /proc/tsp_msg and friends. */
    rputs("=== A51SHIM6 ===\n");
    rputs("Galaxy A51 SM-A515F, Exynos 9611, boot-1 diagnostic shim\n");
    rkv("run", runs);
    rkv("CurrentEL", current_el);
    rkv("SCTLR_EL1", sctlr);
    rkv("MPIDR_EL1", mpidr);
    rkv("ID_AA64MMFR0_EL1", mmfr0);
    rkv("ID_AA64PFR0_EL1", pfr0);
    rkv("CNTFRQ_EL0", cntfrq);
    rkv("CNTPCT_EL0", ticks());
    rkv("FDT_PA", fdt);
    rkv("IMAGE_PA", image_pa);
    rputs("peripherals:\n");
    rkv32("GICD_TYPER@12301004", gicd_typer);
    rkv32("UFS_VERSION@13520008", ufs_ver);
    rkv32("DECON_GLOBAL_CONTROL", decon_ctl);
    rkv32("DECON_SHADOW_REQ", decon_shadow);
    rkv32("DECON_HW_SW_TRIG_CONTROL", decon_trig);
    rkv32("DECON_HW_TE_CNT", decon_te);
    rkv32("DSIM_STATUS", dsim_status);
    rkv32("DPP0_IDMA_IN_BASE_ADDR_Y", dpp0_base);
    rkv32("DPP0_IDMA_SRC_SIZE", dpp0_src);
    rkv32("DPP0_IDMA_ENABLE", dpp0_en);
    rkv("FRAMEBUFFER_PA", FB_BASE);
    probe_dpu();
    struct rtc_snapshot rtc_before;
    rtc_read(&rtc_before);
    rtc_report("before", &rtc_before);
    append_marker("captured");

    /* Prove the FDT walk works against S-Boot's live tree before the kernel
     * handoff depends on it. */
    {
        uint64_t rd_s = 0, rd_e = 0;
        int have_s = fdt_chosen_u64(fdt, "linux,initrd-start", &rd_s);
        int have_e = fdt_chosen_u64(fdt, "linux,initrd-end", &rd_e);
        rkv("fdt_initrd_start_found", (uint64_t)have_s);
        rkv("fdt_initrd_end_found", (uint64_t)have_e);
        rkv("initrd_start", rd_s);
        rkv("initrd_end", rd_e);
        rkv("initrd_size", have_s && have_e ? rd_e - rd_s : 0);
        rkv("payload_magic_ok", (uint64_t)payload_present(fdt, 0));
    }
    emit_report();

    /* If the boot image carries a SWEETXNU payload this is a kernel boot, not a
     * diagnostic one: hand off immediately. Skip the UFS probe (it would take
     * over the transfer request list the kernel expects to re-initialise) and
     * the display dashboard (the kernel owns the framebuffer from here). */
    if (payload_present(fdt, 0)) {
        rputs("\nSWEETXNU payload present in the ramdisk: handing off\n");
        emit_report();
        if (payload_boot(fdt) == 0) {
            for (;;)
                __asm__ volatile("wfe");   /* not reached */
        }
        rputs("payload handoff failed, falling back to diagnostics\n");
        append_marker("payload failed");
        emit_report();
    }

    /* Telemetry that survives even when the RAM log cannot be read back. */
    rtc_write_telemetry(1, (unsigned)runs, 0, decon_ctl, decon_trig,
                        (unsigned)((dpp0_base >> 28) & 0xfU));
    struct rtc_snapshot rtc_after;
    rtc_read(&rtc_after);
    rputs("  rtc telemetry written (marker 41-11-11 11:11:11)\n");
    rtc_report("after", &rtc_after);
    append_marker("rtc written");
    emit_report();

    /* Read-only storage survey. Published before and after so a hang inside
     * the host controller is visible in the recovered report. */
    rputs("\n");
    append_marker("ufs probe start");
    emit_report();
    ufs_probe(rep_kv, rep_out, UFS_DMA_BASE);
    append_marker("ufs probe done");
    emit_report();

    if (runs > 3) {
        /* Three attempts did not get us back into recovery: sit still with the
         * log intact instead of resetting forever. */
        log_field(20, 6);
        append_marker("halted after 3 runs");
        emit_report();
        for (;;)
            __asm__ volatile("wfe");
    }

    struct board_info bi;
    bi.current_el = current_el;
    bi.sctlr = sctlr;
    bi.mpidr = mpidr;
    bi.mmfr0 = mmfr0;
    bi.pfr0 = pfr0;
    bi.cntfrq = cntfrq;
    bi.fdt = fdt;
    bi.image_pa = image_pa;
    bi.gicd_typer = gicd_typer;
    bi.ufs_cap = rd32(UFS + 0x00);
    bi.ufs_ver = ufs_ver;
    bi.decon_ctl = decon_ctl;
    bi.decon_trig = decon_trig;
    bi.decon_te = decon_te;
    bi.dpp_y = dpp0_base;

    paint_dashboard(&bi);
    dcache_clean(FB_BASE, FB_BASE + (uintptr_t)FB_STRIDE * FB_HEIGHT);

    wr32(DECON + SHADOW_REG_UPDATE_REQ,
         rd32(DECON + SHADOW_REG_UPDATE_REQ) | SHADOW_GLOBAL | 0x3fU);
    wr32(DECON + HW_SW_TRIG_CONTROL,
         rd32(DECON + HW_SW_TRIG_CONTROL) | HW_SW_TRIG_TIMER_CLEAR | HW_SW_TRIG_TIMER_EN);
    wr32(DECON + HW_SW_TRIG_CONTROL,
         rd32(DECON + HW_SW_TRIG_CONTROL) | SW_TRIG_EN);

    log_field(20, 2);

    /* Counter band only: 2236..2340 rows, so the refresh is cheap. */
    const uintptr_t band_lo = FB_BASE + (uintptr_t)2236 * FB_STRIDE;
    const uintptr_t band_hi = FB_BASE + (uintptr_t)2340 * FB_STRIDE;

    uint64_t start = ticks();
    uint64_t loops = 0, window_start = start, window_loops = 0;
    uint64_t frames = 0;
    while ((ticks() - start) < (uint64_t)TIMER_HZ * LOOP_SECONDS) {
        uint32_t v = rd32(DECON + HW_SW_TRIG_CONTROL);
        wr32(DECON + HW_SW_TRIG_CONTROL, v | SW_TRIG_EN);
        wr32(DECON + HW_SW_TRIG_CONTROL, v & ~SW_TRIG_EN);
        wr32(DECON + SHADOW_REG_UPDATE_REQ,
             rd32(DECON + SHADOW_REG_UPDATE_REQ) | SHADOW_GLOBAL | 0x3fU);
        if (rd32(DECON + INTERRUPT_PENDING) & BIT(13)) {
            wr32(DECON + INTERRUPT_PENDING, BIT(13));
            frames++;
        }
        loops++;
        if ((ticks() - window_start) >= (uint64_t)TIMER_HZ / 2U) {
            uint64_t now = ticks();
            log_field(21, loops);
            log_field(22, (loops - window_loops) * 200U);
            update_counters((now - start) * 1000U / TIMER_HZ, loops, frames,
                            rd32(DECON + HW_TE_CNT) & 0xffffU, 2);
            dcache_clean(band_lo, band_hi);
            wr32(DECON + SHADOW_REG_UPDATE_REQ,
                 rd32(DECON + SHADOW_REG_UPDATE_REQ) | SHADOW_GLOBAL | 0x3fU);
            window_start = now;
            window_loops = loops;
        }
    }

    log_field(20, 3);
    log_field(21, loops);
    rputs("\nafter trigger loop:\n");
    rputs("  loops(dec) = ");
    rdec(loops);
    rputc('\n');
    rkv("loops", loops);
    rkv("frame_done_events", frames);
    rkv32("DECON_HW_TE_CNT_after", rd32(DECON + HW_TE_CNT));
    rkv32("DECON_HW_SW_TRIG_after", rd32(DECON + HW_SW_TRIG_CONTROL));
    rkv32("DECON_GLOBAL_after", rd32(DECON + GLOBAL_CONTROL));
    rtc_write_telemetry(3, (unsigned)runs, loops,
                        rd32(DECON + GLOBAL_CONTROL),
                        rd32(DECON + HW_SW_TRIG_CONTROL),
                        (unsigned)((dpp0_base >> 28) & 0xfU));
    append_marker("loop done, requesting recovery");
    emit_report();

    recovery_reset();
    log_field(20, 4);
    psci_reset();
    log_field(20, 5);
    append_marker("both resets failed, halting");
    emit_report();
    for (;;)
        __asm__ volatile("wfe");
}
