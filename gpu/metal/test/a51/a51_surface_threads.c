/*
 * Copyright 2026 the ios-a51 contributors
 * SPDX-License-Identifier: MIT
 *
 * rwa_texture_from_surface from several threads at once (review of stages 1-2:
 * air_metal.c's IOSurface cache had no lock; one thread evicting an entry closed
 * the BO's descriptor while another imported from it). Four threads, a device
 * each, import and destroy textures over 32 IOSurfaces -- more than the cache's
 * 24 slots, so lookups and evictions overlap all the time. Every import must
 * succeed.
 *   a51_surface_threads
 */
#include <CoreFoundation/CoreFoundation.h>
#include <IOSurface/IOSurfaceRef.h>
#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>
#include "air_metal.h"

#define NSURF 32
#define NTHREAD 4
#define ROUNDS 400

static IOSurfaceRef surf[NSURF];
static int failures[NTHREAD];
static char first_why[NTHREAD][256];

static void
put_int(CFMutableDictionaryRef d, CFStringRef key, int v)
{
   CFNumberRef n = CFNumberCreate(NULL, kCFNumberIntType, &v);
   CFDictionarySetValue(d, key, n);
   CFRelease(n);
}

static void *
worker(void *arg)
{
   int t = (int)(intptr_t)arg;
   char why[256] = { 0 };
   struct rwa_device *dev = rwa_device_open(why, sizeof(why));
   if (!dev) { failures[t] = ROUNDS; snprintf(first_why[t], 256, "open: %s", why); return NULL; }
   struct rwa_texture_shape shape = {
      .pixel_format = 80, .type = 2, .width = 64, .height = 64, .depth = 1, .array_length = 1,
      .mip_levels = 1, .sample_count = 1, .usage = 1,
   };
   for (int r = 0; r < ROUNDS; r++) {
      IOSurfaceRef s = surf[(r * 7 + t * 5) % NSURF];
      struct rwa_texture *tex = rwa_texture_from_surface(dev, &shape, (int)IOSurfaceGetID(s), 0,
                                                         (unsigned)IOSurfaceGetBytesPerRow(s), why, sizeof(why));
      if (!tex) {
         if (!failures[t]++) snprintf(first_why[t], 256, "%s", why);
         continue;
      }
      rwa_texture_destroy(tex);
   }
   rwa_device_close(dev);
   return NULL;
}

int
main(void)
{
   setvbuf(stdout, NULL, _IONBF, 0);
   for (int i = 0; i < NSURF; i++) {
      CFMutableDictionaryRef d = CFDictionaryCreateMutable(NULL, 0, &kCFTypeDictionaryKeyCallBacks,
                                                           &kCFTypeDictionaryValueCallBacks);
      put_int(d, kIOSurfaceWidth, 64);
      put_int(d, kIOSurfaceHeight, 64);
      put_int(d, kIOSurfaceBytesPerElement, 4);
      put_int(d, kIOSurfaceBytesPerRow, 256);
      put_int(d, kIOSurfacePixelFormat, 0x42475241);
      surf[i] = IOSurfaceCreate(d);
      CFRelease(d);
      if (!surf[i]) { printf("FAIL: IOSurfaceCreate %d\n", i); return 1; }
   }
   pthread_t th[NTHREAD];
   for (int t = 0; t < NTHREAD; t++)
      pthread_create(&th[t], NULL, worker, (void *)(intptr_t)t);
   int total = 0;
   for (int t = 0; t < NTHREAD; t++) {
      pthread_join(th[t], NULL);
      total += failures[t];
      if (failures[t]) printf("thread %d: %d of %d imports failed, first: %s\n", t, failures[t], ROUNDS, first_why[t]);
   }
   printf("surface_threads: %d of %d imports failed\n", total, NTHREAD * ROUNDS);
   return total ? 1 : 0;
}
