// Copyright 2026 the ios-a51 contributors
// SPDX-License-Identifier: MIT
//
// What BGMTLDevice answers for the MTLDevice properties that only Apple's _MTLDevice base class
// implements and iOS 16's QuartzCore reads (mtl_gap -i crossed with QuartzCore's objc_msgSend stubs).
//   a51_device_limits
#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#import <objc/message.h>
#include <stdio.h>

id bgmtl_create_device(void);

int
main(void)
{
   @autoreleasepool {
      id dev = bgmtl_create_device();
      if (!dev) { printf("FAIL: no device\n"); return 1; }
      const char *u[] = { "deviceLinearReadOnlyTextureAlignmentBytes", "iosurfaceReadOnlyTextureAlignmentBytes",
                          "maxColorAttachments", "maxFragmentSamplers", "maxFragmentTextures", "maxTextureHeight2D",
                          "maxTextureWidth2D", "minConstantBufferAlignmentBytes" };
      int zero = 0;
      for (unsigned i = 0; i < sizeof(u) / sizeof(u[0]); i++) {
         NSUInteger v = ((NSUInteger (*)(id, SEL))objc_msgSend)(dev, sel_getUid(u[i]));
         printf("%-44s %lu%s\n", u[i], (unsigned long)v, v ? "" : "   <- FAIL: zero");
         zero += !v;
      }
      const char *b[] = { "supportsMemorylessRenderTargets", "supportsNativeHardwareFP16", "supportsRasterOrderGroups",
                          "supportsSIMDGroup", "supportsTileShaders", "supportsYCBCRFormats12", "supportsYCBCRPackedFormats12" };
      for (unsigned i = 0; i < sizeof(b) / sizeof(b[0]); i++)
         printf("%-44s %s\n", b[i], ((BOOL (*)(id, SEL))objc_msgSend)(dev, sel_getUid(b[i])) ? "YES" : "NO");
      printf("%-44s %s\n", "vendorName", [[dev vendorName] UTF8String] ?: "(nil)");
      BOOL tile = ((BOOL (*)(id, SEL))objc_msgSend)(dev, sel_getUid("supportsTileShaders"));
      printf("== result: %d limits zero%s\n", zero, tile ? ", supportsTileShaders YES (FAIL: no tile shaders on the Mali)" : "");
      return zero || tile ? 1 : 0;
   }
}
