// Fixture for test_air_bifrost.sh: built in the macOS VM with
//   xcrun -sdk iphoneos metal -std=ios-metal2.4 -target air64-apple-ios16.0 quad.metal -o quad.metallib
#include <metal_stdlib>
using namespace metal;

struct VOut {
    float4 position [[position]];
    float2 uv;
};

vertex VOut quad_vertex(uint vid [[vertex_id]], constant float4 *pos [[buffer(0)]])
{
    VOut o;
    o.position = pos[vid];
    o.uv = pos[vid].xy * 0.5 + 0.5;
    return o;
}

fragment float4 quad_fragment(VOut in [[stage_in]], texture2d<float> tex [[texture(0)]],
                              sampler smp [[sampler(0)]])
{
    return tex.sample(smp, in.uv) * float4(in.uv, 1.0, 1.0);
}

constant bool tinted [[function_constant(0)]];

fragment float4 quad_fragment_fc(VOut in [[stage_in]])
{
    return tinted ? float4(in.uv, 0.0, 1.0) : float4(1.0);
}
