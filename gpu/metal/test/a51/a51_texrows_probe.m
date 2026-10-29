// Copyright 2026 the ios-a51 contributors
// SPDX-License-Identifier: MIT
//
// Row order of sampled textures on BGMTLDevice (stage 3, Task 4: CoreAnimation's layer contents came out
// upside down). A 30x7 RGBA8 texture whose row y is filled with the value 0xff000000 | y << 8 | 0x11 is made
// with replaceRegion: and with newTextureWithBytesNoCopy: (rows 128 bytes apart, length rounded up to a page,
// as CoreAnimation passes it), then read on the GPU by coordinate and by normalized sampling. Row 0 must come
// back as row 0 in every case.
//   a51_texrows_probe a51_kernels.metallib
#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#import <objc/message.h>
#include <stdio.h>
#include <string.h>
#include <sys/mman.h>
#include <unistd.h>

id bgmtl_create_device(void);

enum { W = 30, H = 7, BPR = 128 };
static int pass, fail;
#define CHECK(c, ...) do { if (c) pass++; else { fail++; printf("  FAIL: " __VA_ARGS__); printf("\n"); } } while (0)

static uint32_t want(unsigned y) { return 0xff000000u | (y << 8) | 0x11u; }

static void
fill(uint8_t *p)
{
   memset(p, 0x5a, BPR * H);
   for (unsigned y = 0; y < H; y++)
      for (unsigned x = 0; x < W; x++)
         ((uint32_t *)(p + y * BPR))[x] = want(y);
}

static void
check(id<MTLDevice> dev, id<MTLCommandQueue> q, id<MTLComputePipelineState> pso, id<MTLTexture> t, const char *name)
{
   id<MTLBuffer> a = [dev newBufferWithLength:W * H * 4 options:0], b = [dev newBufferWithLength:W * H * 4 options:0];
   MTLSamplerDescriptor *sd = [[MTLSamplerDescriptor alloc] init];
   id<MTLSamplerState> s = [dev newSamplerStateWithDescriptor:sd];
   id<MTLCommandBuffer> cb = [q commandBuffer];
   id<MTLComputeCommandEncoder> e = [cb computeCommandEncoder];
   [e setComputePipelineState:pso];
   [e setTexture:t atIndex:0]; [e setTexture:t atIndex:1]; [e setSamplerState:s atIndex:0];
   [e setBuffer:a offset:0 atIndex:0]; [e setBuffer:b offset:0 atIndex:1];
   [e dispatchThreadgroups:MTLSizeMake((W + 7) / 8, (H + 7) / 8, 1) threadsPerThreadgroup:MTLSizeMake(8, 8, 1)];
   [e endEncoding];
   [cb commit];
   [cb waitUntilCompleted];
   const uint32_t *ca = [a contents], *cs = [b contents];
   int bad_c = 0, bad_s = 0;
   for (unsigned y = 0; y < H; y++)
      for (unsigned x = 0; x < W; x++) {
         bad_c += ca[y * W + x] != want(y);
         bad_s += cs[y * W + x] != want(y);
      }
   printf("%-34s status %ld  row0 by coord %#010x by sample %#010x  last row %#010x  (want %#010x .. %#010x)\n", name,
          (long)cb.status, ca[0], cs[0], ca[(H - 1) * W], want(0), want(H - 1));
   CHECK(bad_c == 0, "%s: %d texels wrong by coordinate", name, bad_c);
   CHECK(bad_s == 0, "%s: %d texels wrong by sampling", name, bad_s);
}

int
main(int argc, char **argv)
{
   @autoreleasepool {
      setvbuf(stdout, NULL, _IONBF, 0);
      id<MTLDevice> dev = bgmtl_create_device();
      if (!dev) { printf("FAIL: no device\n"); return 1; }
      NSError *err = nil;
      NSData *lib = [NSData dataWithContentsOfFile:[NSString stringWithUTF8String:argc > 1 ? argv[1] : "a51_kernels.metallib"]];
      id<MTLLibrary> l = [dev newLibraryWithData:(dispatch_data_t)dispatch_data_create(lib.bytes, lib.length, NULL, DISPATCH_DATA_DESTRUCTOR_DEFAULT) error:&err];
      id<MTLFunction> fn = [l newFunctionWithName:@"texrows"];
      id<MTLComputePipelineState> pso = fn ? [dev newComputePipelineStateWithFunction:fn error:&err] : nil;
      if (!pso) { printf("FAIL: pipeline: %s\n", err ? err.localizedDescription.UTF8String : "no function"); return 1; }
      id<MTLCommandQueue> q = [dev newCommandQueue];

      MTLTextureDescriptor *td = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA8Unorm width:W height:H mipmapped:NO];
      td.usage = MTLTextureUsageShaderRead;
      uint8_t staging[BPR * H];
      fill(staging);
      id<MTLTexture> t1 = [dev newTextureWithDescriptor:td];
      [t1 replaceRegion:MTLRegionMake2D(0, 0, W, H) mipmapLevel:0 withBytes:staging bytesPerRow:BPR];
      check(dev, q, pso, t1, "replaceRegion");

      size_t page = (size_t)getpagesize();
      size_t len = (BPR * H + page - 1) / page * page;   // page-rounded, as CoreAnimation passes it
      uint8_t *mem = mmap(NULL, len, PROT_READ | PROT_WRITE, MAP_ANON | MAP_PRIVATE, -1, 0);
      fill(mem);
      id<MTLTexture> t2 = ((id (*)(id, SEL, void *, NSUInteger, id, id))objc_msgSend)(dev,
         sel_getUid("newTextureWithBytesNoCopy:length:descriptor:deallocator:"), mem, len, td, nil);
      CHECK(t2 != nil, "newTextureWithBytesNoCopy returned nil");
      if (t2) check(dev, q, pso, t2, "newTextureWithBytesNoCopy (paged)");
      printf("== result: %d checks passed, %d failed\n", pass, fail);
      return fail ? 1 : 0;
   }
}
