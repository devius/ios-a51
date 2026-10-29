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

// a51_texrows_probe.m: texel (x, y) of t by coordinate and by normalized sampling, packed RGBA8.
kernel void texrows(texture2d<float, access::read> t [[texture(0)]], texture2d<float> ts [[texture(1)]],
                    sampler s [[sampler(0)]], device uint *by_coord [[buffer(0)]], device uint *by_sample [[buffer(1)]],
                    uint2 gid [[thread_position_in_grid]])
{
    uint w = t.get_width(), h = t.get_height();
    if (gid.x >= w || gid.y >= h) return;
    float4 c = t.read(gid);
    float4 d = ts.sample(s, (float2(gid) + 0.5) / float2(w, h));
    uint4 a = uint4(round(saturate(c) * 255.0)), b = uint4(round(saturate(d) * 255.0));
    by_coord[gid.y * w + gid.x] = a.x | a.y << 8 | a.z << 16 | a.w << 24;
    by_sample[gid.y * w + gid.x] = b.x | b.y << 8 | b.z << 16 | b.w << 24;
}

// a51_render_diag.c case 6: a fragment stage that writes only the second colour attachment.
struct A51Out1 { float4 c1 [[color(1)]]; };
fragment A51Out1 a51_fs_color1()
{
    A51Out1 o;
    o.c1 = float4(0.0, 0.0, 1.0, 1.0);
    return o;
}

// a51_render_diag.c case 7: writes both attachments; colour 0's write mask is 0, so only colour 1 may change.
struct A51Out01 { float4 c0 [[color(0)]]; float4 c1 [[color(1)]]; };
fragment A51Out01 a51_fs_color01()
{
    A51Out01 o;
    o.c0 = float4(1.0, 0.0, 0.0, 1.0);
    o.c1 = float4(0.0, 0.0, 1.0, 1.0);
    return o;
}

// a51_render_diag.c case 8: CoreAnimation's coverage pass shape: reads colour 0 (framebuffer fetch), writes
// only colour 1, colour 0 masked off. Colour 1 must get colour 0's clear value, swapped to blue-red-green.
fragment A51Out1 a51_fs_fetch0_to1(float4 c0 [[color(0)]])
{
    A51Out1 o;
    o.c1 = float4(c0.b, 1.0, c0.g, 1.0);
    return o;
}

// a51_render_diag.c cases 9 and 10: CoreAnimation's composite shape: read colour 0 (and 1) by framebuffer fetch
// and write colour 0 -- as half (9, CA's f16vec4 outputs) and as float (10). Colour 0 inside the triangle
// must become (clear.b, 1, clear.g).
struct A51OutH0 { half4 c0 [[color(0)]]; };
fragment A51OutH0 a51_fs_fetch0_half(half4 c0 [[color(0)]], float4 c1 [[color(1)]])
{
    A51OutH0 o;
    o.c0 = half4(c0.b, 1.0h, c0.g, 1.0h + half(c1.a) * 0.0h);
    return o;
}
struct A51OutF0 { float4 c0 [[color(0)]]; };
fragment A51OutF0 a51_fs_fetch0_float(float4 c0 [[color(0)]], float4 c1 [[color(1)]])
{
    A51OutF0 o;
    o.c0 = float4(c0.b, 1.0, c0.g, 1.0 + c1.a * 0.0);
    return o;
}

// a51_render_diag.c case 11: the composite's other half: read colour 1 (not written), write colour 0.
fragment A51OutH0 a51_fs_fetch1_to0(half4 c0 [[color(0)]], half4 c1 [[color(1)]])
{
    A51OutH0 o;
    o.c0 = half4(c1.b, c0.a, c1.g, 1.0h);
    return o;
}

// a51_render_diag.c case 12: screen-space derivatives (CoreAnimation's anti-aliased corners use fwidth).
// d(position.x)/dx = 1 and d(position.y)/dy = 1: red = 0.5 * dfdx(x) -> 128, green = 0.25 * dfdy(y) -> 64,
// blue = 0.125 * fwidth(x + y) -> 0.125 * 2 -> 64.
fragment float4 a51_fs_derivs(float4 p [[position]])
{
    return float4(0.5 * dfdx(p.x), 0.25 * dfdy(p.y), 0.125 * fwidth(p.x + p.y), 1.0);
}

// a51_render_diag.c case 13: case 8 with CoreAnimation's types: half4 in, half4 out to colour 1.
struct A51OutH1 { half4 c1 [[color(1)]]; };
fragment A51OutH1 a51_fs_fetch0_to1_half(half4 c0 [[color(0)]])
{
    A51OutH1 o;
    o.c1 = half4(c0.b, 1.0h, c0.g, 1.0h);
    return o;
}
