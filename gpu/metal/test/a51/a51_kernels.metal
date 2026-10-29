// Kernels for a51_device_test.c, built in the macOS VM with
//   xcrun -sdk iphoneos metal -std=ios-metal2.4 -target air64-apple-ios16.0 a51_kernels.metal -o a51_kernels.metallib
#include <metal_stdlib>
using namespace metal;

kernel void fill(device uint *out [[buffer(0)]], uint id [[thread_position_in_grid]])
{
    out[id] = id * 3u + 7u;
}

// Writes far past its buffer: out[far] with far = 1 << 28 words is 1 GiB away,
// outside every mapping of the GPU address space, so the GPU must fault.
kernel void poke(device uint *out [[buffer(0)]], constant uint &far [[buffer(1)]])
{
    out[far] = 1u;
}
