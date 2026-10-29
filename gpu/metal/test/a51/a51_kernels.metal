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

// a51_surface_test.c: pixel (x, y) of a BGRA8Unorm texture gets bytes x, y, 0, 255.
kernel void paint(texture2d<float, access::write> t [[texture(0)]], uint2 gid [[thread_position_in_grid]])
{
    if (gid.x < t.get_width() && gid.y < t.get_height())
        t.write(float4(0.0, float(gid.y) / 255.0, float(gid.x) / 255.0, 1.0), gid);
}

// a51_render_diag.c: a fixed lower-left triangle, and a solid red fragment.
vertex float4 a51_vs_tri(uint vid [[vertex_id]])
{
    const float2 p[3] = { float2(-1.0, -1.0), float2(1.0, -1.0), float2(-1.0, 1.0) };
    return float4(p[vid], 0.0, 1.0);
}

fragment float4 a51_fs_red()
{
    return float4(1.0, 0.0, 0.0, 1.0);
}

// a51_render_diag.c case 5: a cross of two lines through the centre (line list, 4 vertices).
vertex float4 a51_vs_cross(uint vid [[vertex_id]])
{
    const float2 p[4] = { float2(-1.0, 0.0), float2(1.0, 0.0), float2(0.0, -1.0), float2(0.0, 1.0) };
    return float4(p[vid], 0.0, 1.0);
}
