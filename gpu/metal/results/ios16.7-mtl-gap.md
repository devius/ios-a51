# BGMTLDevice against iOS 16.7's Metal (stage 3, Task 3)

2026-10-29, `mtl_gap -v` / `mtl_gap -i` on the phone (iOS 16.7.16 20H392), crossed with the
`_objc_msgSend$…` selector stubs of iOS 16.7's QuartzCore (dyld cache).

## Unanswered selectors QuartzCore calls

Of 24 selectors no class in the chain answers (MTLDevice 5, MTLDeviceSPI 11, MTLCommandBuffer 4,
MTLBuffer 4), QuartzCore calls one: `newHeapWithDescriptor:`. Apple's base answered it with an
empty heap (size 0, every allocation nil; a51_heap_probe red). Now `BGMTLHeap` (src/bgmtl.m):
resources are the device's own, no aliasing. a51_heap_probe 7/7.

## Answered only by Apple's base class, called by QuartzCore

27 of 377. The numeric limits came back as **0** (a51_device_limits); bgmtl.m now answers:

| Selector | Was | Now |
|---|---|---|
| maxColorAttachments | 0 | 8 |
| maxFragmentTextures, maxFragmentSamplers | 0 | 16 |
| maxTextureWidth2D, maxTextureHeight2D | 0 | 8192 |
| minConstantBufferAlignmentBytes | 0 | 256 |
| deviceLinearReadOnlyTextureAlignmentBytes, iosurfaceReadOnlyTextureAlignmentBytes | 0 | 64 |

Left to the base (NO / its own code): supportsMemorylessRenderTargets, supportsNativeHardwareFP16,
supportsRasterOrderGroups, supportsSIMDGroup, supportsTileShaders (NO keeps CoreAnimation off the
tile kernels that do not compile for the Mali), supportsYCBCRFormats12/PackedFormats12, vendorName
("Apple"), newCommandQueue, label/setLabel:, debug groups and signposts, command-buffer timestamps
(GPUStartTime, GPUEndTime, kernelStartTime, kernelEndTime), and
newRenderPipelineStateWithTileDescriptor:options:reflection:error: (tile pipelines: not requested
while supportsTileShaders is NO).
