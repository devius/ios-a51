/*
 * Copyright 2026 the ios-a51 contributors
 * SPDX-License-Identifier: MIT
 *
 * air_metal.c on the A51's Mali (plan Task 4): device name, two devices in one
 * process, and a GPU fault that must come back as an error.
 *   a51_device_test a51_kernels.metallib
 * The metallib reader is bgair_test.c's (Chlorophyll, MIT).
 */
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "air_metal.h"

unsigned long long herodrm_fault_count(void);

static int pass, fail;
#define CHECK(c, ...) do { if (c) { pass++; } else { fail++; printf("  FAIL: " __VA_ARGS__); printf("\n"); } } while (0)

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

static const uint8_t *lib;
static size_t libsize;

static struct rwa_compute *
pipeline(struct rwa_device *dev, const char *fn)
{
   size_t sz;
   const uint8_t *bc = metallib_function(lib, libsize, fn, &sz);
   struct rwa_compute_info info;
   char why[512] = { 0 };
   if (!bc) { printf("  no function %s\n", fn); return NULL; }
   struct rwa_compute *c = rwa_compute_create(dev, bc, sz, fn, &info, why, sizeof(why));
   if (!c) printf("  rwa_compute_create(%s): %s\n", fn, why);
   return c;
}

/* fill on dev: 256 words, every one id*3+7; 1 if exact */
static int
fill_exact(struct rwa_device *dev)
{
   char why[512] = { 0 };
   struct rwa_compute *c = pipeline(dev, "fill");
   struct rwa_buffer *b = rwa_buffer_create(dev, 256 * 4, why, sizeof(why));
   if (!c || !b) { printf("  fill setup: %s\n", why); return 0; }
   uint32_t *m = rwa_buffer_map(b);
   memset(m, 0xab, 256 * 4);
   struct rwa_buffer *bufs[] = { b };
   struct rwa_bindings bind = { .buffers = bufs, .buffer_count = 1 };
   unsigned groups[3] = { 4, 1, 1 }, size[3] = { 64, 1, 1 };
   int r = rwa_dispatch(c, &bind, groups, size, why, sizeof(why));
   if (r == 0) r = rwa_finish(dev, why, sizeof(why));
   int bad = 0;
   for (unsigned i = 0; r == 0 && i < 256; i++)
      bad += m[i] != i * 3 + 7;
   if (r) printf("  fill: %s\n", why);
   else if (bad) printf("  fill: %d of 256 words wrong (m[0]=%#x m[255]=%#x)\n", bad, m[0], m[255]);
   rwa_buffer_destroy(b);
   rwa_compute_destroy(c);
   return r == 0 && bad == 0;
}

int
main(int argc, char **argv)
{
   const char *path = argc > 1 ? argv[1] : "a51_kernels.metallib";
   FILE *f = fopen(path, "rb");
   if (!f) { perror(path); return 2; }
   fseek(f, 0, SEEK_END);
   libsize = ftell(f);
   rewind(f);
   uint8_t *b = malloc(libsize);
   if (fread(b, 1, libsize, f) != libsize) { printf("short read\n"); return 2; }
   fclose(f);
   lib = b;

   char why[512] = { 0 };
   struct rwa_device *dev = rwa_device_open(why, sizeof(why));
   if (!dev) { printf("FAIL: no device: %s\n", why); return 1; }

   printf("device_name_is_mali: %s\n", rwa_device_name(dev));
   CHECK(strstr(rwa_device_name(dev), "Mali-G72") != NULL, "device_name_is_mali: \"%s\"", rwa_device_name(dev));

   struct rwa_device *dev2 = rwa_device_open(why, sizeof(why));
   CHECK(dev2 != NULL, "device_open_twice: second open: %s", why);
   if (dev2) {
      CHECK(fill_exact(dev), "device_open_twice: dispatch on the first device");
      CHECK(fill_exact(dev2), "device_open_twice: dispatch on the second device");
      rwa_device_close(dev2);
      CHECK(fill_exact(dev), "device_open_twice: first device after closing the second");
   }

   /* compute_fault_reported: poke writes 1 GiB past its buffer */
   unsigned long long faults0 = herodrm_fault_count();
   struct rwa_compute *poke = pipeline(dev, "poke");
   struct rwa_buffer *out = rwa_buffer_create(dev, 4096, why, sizeof(why));
   struct rwa_buffer *far = rwa_buffer_create(dev, 16, why, sizeof(why));
   if (poke && out && far) {
      *(uint32_t *)rwa_buffer_map(far) = 1u << 28;
      struct rwa_buffer *bufs[] = { out, far };
      struct rwa_bindings bind = { .buffers = bufs, .buffer_count = 2 };
      unsigned groups[3] = { 1, 1, 1 }, size[3] = { 1, 1, 1 };
      why[0] = 0;
      int r = rwa_dispatch(poke, &bind, groups, size, why, sizeof(why));
      if (r == 0) r = rwa_finish(dev, why, sizeof(why));
      printf("compute_fault_reported: r=%d why=\"%s\" faults %llu -> %llu\n", r, why, faults0, herodrm_fault_count());
      CHECK(r != 0 && why[0], "compute_fault_reported: the faulting dispatch returned %d", r);
      CHECK(herodrm_fault_count() > faults0, "compute_fault_reported: herodrm saw no fault");
   } else {
      CHECK(0, "compute_fault_reported: setup: %s", why);
   }

   printf("%d passed, %d failed\n", pass, fail);
   return fail ? 1 : 0;
}
