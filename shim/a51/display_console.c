/*
 * Display console for A51 shim - draws color bars and diagnostic text
 * Based on dreamlte display_console.c with A51 adaptations
 */

#include <stdint.h>
#include <string.h>

#define FB_BASE     0xCA000000UL
#define FB_W        1080
#define FB_H        2400
#define FB_STRIDE   (FB_W * 4)
#define PAGE_SIZE   4096UL

static volatile uint32_t *fb = (volatile uint32_t *)FB_BASE;

static void flush_dcache(void *addr, uint32_t size)
{
    uint64_t end = (uint64_t)addr + size;
    uint64_t line = 4UL << ((CSSELR_EL1 & 0xf) << 2);

    for (uint64_t p = (uint64_t)addr & ~(line - 1); p < end; p += line)
        __asm__ volatile("dc cvac, %0" : : "r" (p) : "memory");

    __asm__ volatile("dsb sy" : : "memory");
}

static void draw_pixel(int x, int y, uint32_t color)
{
    if (x < 0 || x >= FB_W || y < 0 || y >= FB_H)
        return;
    fb[y * FB_W + x] = color;
}

static void draw_line(int x0, int y0, int x1, int y1, uint32_t color)
{
    int dx = x1 - x0;
    int dy = y1 - y0;
    int steps = (dx > dy) ? dx : dy;
    if (steps == 0) {
        draw_pixel(x0, y0, color);
        return;
    }
    float xinc = (float)dx / steps;
    float yinc = (float)dy / steps;
    float x = x0, y = y0;
    for (int i = 0; i <= steps; i++) {
        draw_pixel((int)(x + 0.5), (int)(y + 0.5), color);
        x += xinc;
        y += yinc;
    }
}

static void draw_rect(int x, int y, int w, int h, uint32_t color)
{
    for (int i = 0; i < h; i++)
        for (int j = 0; j < w; j++)
            draw_pixel(x + j, y + i, color);
}

static void draw_string(int x, int y, const char *text, uint32_t color, uint32_t bg_color)
{
    /* Simple bitmap font rendering */
    for (int i = 0; text[i]; i++) {
        int c = text[i] - ' ';
        if (c < 0 || c >= 96)
            continue;
        /* Simple char rendering */
        for (int j = 0; j < 8; j++) {
            uint32_t mask = 0x80 >> j;
            for (int k = 0; k < 6; k++) {
                int bit = (font8x6[c][j] >> k) & 1;
                if (bit) {
                    draw_pixel(x + k * 2, y + j, color);
                } else {
                    draw_pixel(x + k * 2, y + j, bg_color);
                }
            }
        }
        x += 12;
    }
}

static void draw_color_bars(void)
{
    /* Red bar on top third */
    draw_rect(0, 0, FB_W, FB_H / 3, 0xFF0000UL);
    /* Green bar on middle third */
    draw_rect(0, FB_H / 3, FB_W, FB_H / 3, 0x00FF00UL);
    /* Blue bar on bottom third */
    draw_rect(0, (FB_H / 3) * 2, FB_W, FB_H / 3, 0x0000FFUL);
    /* White diagonal line */
    draw_line(0, 0, FB_W - 1, FB_H - 1, 0xFFFFFFFFUL);
}

static void draw_diagnostic_text(void)
{
    int y = 20;
    draw_string(10, y, "HACKIOS SHIM A51 REV8 OK", 0xFFFFFFUL, 0x000000UL);
    y += 30;
    draw_string(10, y, "CurrentEL: ?", 0xFFFF00UL, 0x000000UL);
    y += 30;
    draw_string(10, y, "SCTLR_EL1: ?", 0x00FFFFUL, 0x000000UL);
    y += 30;
    draw_string(10, y, "MPIDR_EL1: ?", 0xFF00FFUL, 0x000000UL);
    y += 30;
    draw_string(10, y, "DECON @ 0x148B0000", 0xFFFFFFUL, 0x000000UL);
    y += 30;
    draw_string(10, y, "Timer: 26 MHz (0x18CBA80)", 0xFFFFFFUL, 0x000000UL);
    y += 30;
    draw_string(10, y, "DRAM: 0x880000000 (2 GB)", 0xFFFFFFUL, 0x000000UL);
}

void draw_diagnostic_screen(void)
{
    draw_color_bars();
    draw_diagnostic_text();
    flush_dcache(fb, FB_W * FB_H * 4);
}

/* DECON trigger functions */
static void decon_write(uint32_t reg, uint32_t value)
{
    volatile uint32_t *decon = (volatile uint32_t *)(0x148B0000UL + reg);
    decon[0] = value;
    flush_dcache(decon, 4);
}

void trigger_decon_update(void)
{
    /* Write to DECON registers to trigger frame update */
    /* This is based on S8 DECON trigger sequence */
    decon_write(0x0070, 0x00000400);  /* HW_SW_TRIG_CONTROL */
    decon_write(0x0074, 0x00000001);  /* HW_SW_TRIG_TIMER */
    /* Wait for completion */
    for (int i = 0; i < 1000; i++)
        if (decon_read(0x0070) & 0x00000400)
            break;
}

static uint32_t decon_read(uint32_t reg)
{
    return ((volatile uint32_t *)(0x148B0000UL + reg))[0];
}

void setup_decon_trigger(void)
{
    /* Configure DECON for command mode (psr_mode=2) */
    decon_write(0x0070, 0x00000008);  /* SW_TRIG_EN */
    decon_write(0x0070, 0x00000009);  /* SW_TRIG_EN + timer enable */
}