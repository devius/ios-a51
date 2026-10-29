// Copyright 2026 the ios-a51 contributors
// SPDX-License-Identifier: MIT
//
// BGMTLDevice's MTLHeap through Metal's API (stage 3, Task 3): a 1 MiB private heap,
// a buffer and a texture from it, both usable, usedSize counted.
//   a51_heap_probe
#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#include <stdio.h>
#include <string.h>

id bgmtl_create_device(void);

int
main(void)
{
   @autoreleasepool {
      int pass = 0, fail = 0;
#define CHECK(c, ...) do { if (c) pass++; else { fail++; printf("  FAIL: " __VA_ARGS__); printf("\n"); } } while (0)
      id<MTLDevice> dev = bgmtl_create_device();
      if (!dev) { printf("FAIL: no device\n"); return 1; }
      MTLHeapDescriptor *hd = [[MTLHeapDescriptor alloc] init];
      hd.size = 1 << 20;
      hd.storageMode = MTLStorageModeShared;
      id<MTLHeap> heap = [dev newHeapWithDescriptor:hd];
      CHECK(heap != nil, "newHeapWithDescriptor: returned nil");
      CHECK(heap.size == (1 << 20), "heap size %lu", (unsigned long)heap.size);
      id<MTLBuffer> b = [heap newBufferWithLength:4096 options:MTLResourceStorageModeShared];
      CHECK(b != nil && b.length >= 4096, "heap buffer");
      if (b) { memset(b.contents, 0x3c, 4096); CHECK(((unsigned char *)b.contents)[4095] == 0x3c, "heap buffer contents"); }
      MTLTextureDescriptor *td = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatBGRA8Unorm
                                                                                     width:64 height:64 mipmapped:NO];
      td.storageMode = MTLStorageModeShared;
      id<MTLTexture> t = [heap newTextureWithDescriptor:td];
      CHECK(t != nil && t.width == 64, "heap texture");
      CHECK(heap.usedSize > 0 && heap.usedSize <= heap.size, "usedSize %lu", (unsigned long)heap.usedSize);
      CHECK([heap maxAvailableSizeWithAlignment:256] == heap.size - heap.usedSize, "maxAvailableSize");
      printf("heap: size %lu used %lu, buffer %s, texture %s\n", (unsigned long)heap.size, (unsigned long)heap.usedSize,
             b ? "ok" : "nil", t ? "ok" : "nil");
      printf("== result: %d checks passed, %d failed\n", pass, fail);
      return fail ? 1 : 0;
   }
}
