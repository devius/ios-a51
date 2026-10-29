/*
 * Copyright 2026 the ios-a51 contributors
 * SPDX-License-Identifier: MIT
 *
 * IOSurface import on the A51's Mali (plan Task 5): a kernel writes into an
 * IOSurface's own memory through rwa_texture_from_surface, the CPU reads the
 * surface back. Pixel (x, y) must be the bytes x, y, 0, 255 (BGRA8Unorm);
 * a row's padding past width x 4 bytes must keep the 0x5a it was filled with.
 *   a51_surface_test a51_kernels.metallib
 */
#include <CoreFoundation/CoreFoundation.h>
#include <IOSurface/IOSurfaceRef.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "air_metal.h"

#define MTL_PIXEL_FORMAT_BGRA8_UNORM 80
#define MTL_TEXTURE_TYPE_2D 2
#define MTL_USAGE_SHADER_READ 1
#define MTL_USAGE_SHADER_WRITE 2

static int pass, fail;
#define CHECK(c, ...) do { if (c) { pass++; } else { fail++; printf("  FAIL: " __VA_ARGS__); printf("\n"); } } while (0)

/* bgair_test.c's metallib reader (Chlorophyll, MIT) */
static uint64_t rd64(const uint8_t *p) { uint64_t v = 0; for (int i = 7; i >= 0; i--) v = v << 8 | p[i]; return v; }
static uint32_t rd32(const uint8_t *p) { return p[0] | p[1] << 8 | p[2] << 16 | (uint32_t)p[3] << 24; }
static uint16_t rd16(const uint8_t *p) { return p[0] | p[1] << 8; }

static const uint8_t *
metallib_function(const uint8_t *b, size_t size, const char *want, size_t *out_size)
{
   if (size < 0x58 || memcmp(b, "MTLB", 4)) return NULL;
   uint64_t funcs = rd64(b + 0x18), bc_off = rd64(b + 0x48), bc_len = rd64(b + 0x50);
   const uint8_t *p = b + funcs;
   uint32_t count = rd32(p);
   p += 4;
   for (uint32_t i = 0; i < count; i++) {
      uint32_t len = rd32(p);
      const uint8_t *q = p + 4, *end = p + len;
      char name[128] = { 0 };
      uint64_t off = 0, sz = 0;
      while (q + 6 <= end && memcmp(q, "ENDT", 4)) {
         uint16_t vlen = rd16(q + 4);
         const uint8_t *v = q + 6;
         if (!memcmp(q, "NAME", 4)) memcpy(name, v, vlen < 127 ? vlen : 127);
         else if (!memcmp(q, "OFFT", 4) && vlen >= 24) off = rd64(v + 16);
         else if (!memcmp(q, "MDSZ", 4) && vlen >= 8) sz = rd64(v);
         q = v + vlen;
      }
      if (!strcmp(name, want) && off + sz <= bc_len) { *out_size = sz; return b + bc_off + off; }
      p = end;
   }
   return NULL;
}

static void
put_int(CFMutableDictionaryRef d, CFStringRef key, int v)
{
   CFNumberRef n = CFNumberCreate(NULL, kCFNumberIntType, &v);
   CFDictionarySetValue(d, key, n);
   CFRelease(n);
}

static IOSurfaceRef
make_surface(int w, int h, int bpr)
{
   CFMutableDictionaryRef d = CFDictionaryCreateMutable(NULL, 0, &kCFTypeDictionaryKeyCallBacks,
                                                        &kCFTypeDictionaryValueCallBacks);
   put_int(d, kIOSurfaceWidth, w);
   put_int(d, kIOSurfaceHeight, h);
   put_int(d, kIOSurfaceBytesPerElement, 4);
   put_int(d, kIOSurfaceBytesPerRow, bpr);
   put_int(d, kIOSurfacePixelFormat, 0x42475241);   /* 'BGRA' */
   IOSurfaceRef s = IOSurfaceCreate(d);
   CFRelease(d);
   return s;
}

static struct rwa_device *dev;
static struct rwa_compute *paint;

/* name: the test; w, h, bpr: the surface */
static void
surface_case(const char *name, int w, int h, int bpr)
{
   char why[512] = { 0 };
   IOSurfaceRef s = make_surface(w, h, bpr);
   if (!s) { CHECK(0, "%s: IOSurfaceCreate(%dx%d, %d bytes a row) failed", name, w, h, bpr); return; }
   int real_bpr = (int)IOSurfaceGetBytesPerRow(s);
   printf("%s: IOSurface %u, %d bytes a row, %zu bytes\n", name, IOSurfaceGetID(s), real_bpr, IOSurfaceGetAllocSize(s));
   IOSurfaceLock(s, 0, NULL);
   memset(IOSurfaceGetBaseAddress(s), 0x5a, IOSurfaceGetAllocSize(s));
   IOSurfaceUnlock(s, 0, NULL);

   struct rwa_texture_shape shape = {
      .pixel_format = MTL_PIXEL_FORMAT_BGRA8_UNORM, .type = MTL_TEXTURE_TYPE_2D,
      .width = w, .height = h, .depth = 1, .array_length = 1, .mip_levels = 1, .sample_count = 1,
      .usage = MTL_USAGE_SHADER_READ | MTL_USAGE_SHADER_WRITE,
   };
   struct rwa_texture *t = rwa_texture_from_surface(dev, &shape, (int)IOSurfaceGetID(s), 0, real_bpr,
                                                    why, sizeof(why));
   if (!t) { CHECK(0, "%s: rwa_texture_from_surface: %s", name, why); CFRelease(s); return; }
   printf("%s: imported\n", name);
   struct rwa_texture *texs[] = { t };
   struct rwa_bindings bind = { .textures = texs, .texture_count = 1 };
   unsigned groups[3] = { (w + 7) / 8, (h + 7) / 8, 1 }, size[3] = { 8, 8, 1 };
   int r = rwa_dispatch(paint, &bind, groups, size, why, sizeof(why));
   if (r == 0) r = rwa_finish(dev, why, sizeof(why));
   if (r == 0) r = rwa_texture_flush_surface(t);
   CHECK(r == 0, "%s: dispatch: %s", name, why);

   IOSurfaceLock(s, kIOSurfaceLockReadOnly, NULL);
   const uint8_t *base = IOSurfaceGetBaseAddress(s);
   int bad = 0, bad_pad = 0;
   for (int y = 0; y < h; y++) {
      const uint32_t *row = (const uint32_t *)(base + (size_t)y * real_bpr);
      for (int x = 0; x < w; x++)
         if (row[x] != ((uint32_t)x | (uint32_t)y << 8 | 0xff000000u)) {
            if (!bad) printf("  %s: first wrong pixel (%d,%d) = %#010x\n", name, x, y, row[x]);
            bad++;
         }
      for (int b = w * 4; b < real_bpr; b++)
         bad_pad += base[(size_t)y * real_bpr + b] != 0x5a;
   }
   IOSurfaceUnlock(s, kIOSurfaceLockReadOnly, NULL);
   printf("%s: %dx%d, %d bytes a row: %d wrong pixels, %d padding bytes changed\n", name, w, h, real_bpr, bad, bad_pad);
   CHECK(bad == 0, "%s: %d of %d pixels wrong", name, bad, w * h);
   CHECK(bad_pad == 0, "%s: %d padding bytes changed", name, bad_pad);
   rwa_texture_destroy(t);
   CFRelease(s);
}

int
main(int argc, char **argv)
{
   setvbuf(stdout, NULL, _IONBF, 0);
   const char *path = argc > 1 ? argv[1] : "a51_kernels.metallib";
   FILE *f = fopen(path, "rb");
   if (!f) { perror(path); return 2; }
   fseek(f, 0, SEEK_END);
   size_t libsize = ftell(f);
   rewind(f);
   uint8_t *lib = malloc(libsize);
   if (fread(lib, 1, libsize, f) != libsize) { printf("short read\n"); return 2; }
   fclose(f);

   char why[512] = { 0 };
   dev = rwa_device_open(why, sizeof(why));
   if (!dev) { printf("FAIL: no device: %s\n", why); return 1; }
   size_t sz;
   const uint8_t *bc = metallib_function(lib, libsize, "paint", &sz);
   struct rwa_compute_info info;
   paint = bc ? rwa_compute_create(dev, bc, sz, "paint", &info, why, sizeof(why)) : NULL;
   if (!paint) { printf("FAIL: paint: %s\n", bc ? why : "no function"); return 1; }

   surface_case("surface_roundtrip", 64, 64, 256);
   surface_case("surface_padded_rows", 30, 7, 128);

   printf("%d passed, %d failed\n", pass, fail);
   return fail ? 1 : 0;
}
