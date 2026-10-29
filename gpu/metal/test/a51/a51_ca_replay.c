/*
 * Copyright 2026 the ios-a51 contributors
 * SPDX-License-Identifier: MIT
 *
 * Replays one draw of CoreAnimation's rounded-clip composite (bgmtl_carenderer_probe scene 3, dumped with
 * BGMTL_TRACE=1 BGMTL_DUMP: NNN-fixed_vert_lph_spc.v.bc + NNN-fixed_frag_lph_cpf.f.bc) on the Mali with the
 * inputs the trace recorded: the top-left corner patch (40..80, 40..80), a1 the corner circle's coordinates,
 * colour 0 holding the background, colour 1 (CA's coverage) zero. Outside the circle (40,40) colour 0 must stay
 * the background: on the phone that draw turned it into (0,0,0,0).
 *   a51_ca_replay VERTEX.v.bc FRAGMENT.f.bc [cov_alpha [masks]]   (a stage may be LIB.metallib:FUNCTION)
 * masks: colour 0 and 1 write masks as "c0,c1" (default 15,0, the composite); 0,15 is the coverage pass (001),
 * which reads colour 0 and writes colour 1 -- then colour 1 is printed too.
 */
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "air_metal.h"

static uint8_t *
slurp(const char *path, size_t *n)
{
   FILE *f = fopen(path, "rb");
   if (!f) { perror(path); exit(2); }
   fseek(f, 0, SEEK_END);
   *n = ftell(f);
   rewind(f);
   uint8_t *b = malloc(*n);
   if (fread(b, 1, *n, f) != *n) exit(2);
   fclose(f);
   return b;
}

/* "LIB.metallib:FUNCTION": that function's module (bgair_test.c's reader, Chlorophyll, MIT) */
static uint64_t rd64(const uint8_t *p) { uint64_t v = 0; for (int i = 7; i >= 0; i--) v = v << 8 | p[i]; return v; }
static uint32_t rd32(const uint8_t *p) { return p[0] | p[1] << 8 | p[2] << 16 | (uint32_t)p[3] << 24; }
static uint16_t rd16(const uint8_t *p) { return p[0] | p[1] << 8; }
static uint8_t *
function_of(uint8_t *b, const char *want, size_t *out)
{
   uint64_t funcs = rd64(b + 0x18), bc_off = rd64(b + 0x48);
   const uint8_t *p = b + funcs;
   uint32_t count = rd32(p); p += 4;
   for (uint32_t i = 0; i < count; i++) {
      uint32_t len = rd32(p); const uint8_t *q = p + 4, *end = p + len; char name[128] = { 0 }; uint64_t off = 0, sz = 0;
      while (q + 6 <= end && memcmp(q, "ENDT", 4)) {
         uint16_t vl = rd16(q + 4); const uint8_t *v = q + 6;
         if (!memcmp(q, "NAME", 4)) memcpy(name, v, vl < 127 ? vl : 127);
         else if (!memcmp(q, "OFFT", 4) && vl >= 24) off = rd64(v + 16);
         else if (!memcmp(q, "MDSZ", 4) && vl >= 8) sz = rd64(v);
         q = v + vl;
      }
      if (!strcmp(name, want)) { *out = sz; return b + bc_off + off; }
      p = end;
   }
   printf("no function %s\n", want);
   exit(2);
}

static uint8_t *
load_stage(char *spec, size_t *n)
{
   char *colon = strstr(spec, ".metallib:");
   if (!colon) return slurp(spec, n);
   colon[9] = 0;
   uint8_t *lib = slurp(spec, n);
   return function_of(lib, colon + 10, n);
}

static void
put_half(uint8_t *p, float v)
{
   __fp16 h = (__fp16)v;
   memcpy(p, &h, 2);
}

int
main(int argc, char **argv)
{
   setvbuf(stdout, NULL, _IONBF, 0);
   if (argc < 3) { printf("usage: a51_ca_replay VERTEX.v.bc FRAGMENT.f.bc [cov_alpha 0..255]\n"); return 2; }
   unsigned cov_alpha = argc > 3 ? (unsigned)atoi(argv[3]) : 0;
   unsigned m0 = 15, m1 = 0;
   if (argc > 4) sscanf(argv[4], "%u,%u", &m0, &m1);
   size_t vs, fs;
   uint8_t *vb = load_stage(argv[1], &vs), *fb = load_stage(argv[2], &fs);
   char why[512] = { 0 };
   struct rwa_device *dev = rwa_device_open(why, sizeof(why));
   if (!dev) { printf("device: %s\n", why); return 3; }

   struct rwa_render_shape shape;
   memset(&shape, 0, sizeof(shape));
   shape.color_format[0] = 80; shape.color_format[1] = 80; shape.color_count = 2; shape.sample_count = 1;
   shape.color_blend[0].write_mask = m0; shape.color_blend[1].write_mask = m1; shape.color_blend_count = 2;
   shape.vertex_attribute[0] = (struct rwa_vertex_attribute){ 31, 0, 1 };    /* float4 position */
   shape.vertex_attribute[1] = (struct rwa_vertex_attribute){ 29, 16, 1 };   /* float2 a1 */
   shape.vertex_attribute[2] = (struct rwa_vertex_attribute){ 29, 24, 1 };   /* float2 a2 */
   shape.vertex_attribute[3] = (struct rwa_vertex_attribute){ 27, 32, 1 };   /* half4 colour */
   shape.vertex_layout[1].stride = 48; shape.vertex_layout[1].step_function = 1; shape.vertex_layout[1].step_rate = 1;
   struct rwa_render_info info;
   memset(&info, 0, sizeof(info));
   struct rwa_render *r = rwa_render_create(dev, vb, vs, NULL, fb, fs, NULL, &shape, &info, why, sizeof(why));
   if (!r) { printf("rwa_render_create: %s\n", why); return 1; }
   printf("pipeline: vertex_buffers=%u fragment_buffers=%u textures=%u streams=%u\n", info.vertex_buffers,
          info.fragment_buffers, info.fragment_textures, info.vertex_streams);

   /* the corner patch, two triangles, as the trace recorded it (a1: circle coordinates, a2: pixels) */
   const float quad[4][6] = { { 40, 40, -1, -1, 1, 1 }, { 80, 40, 0, -1, 41, 1 }, { 80, 80, 0, 0, 41, 41 }, { 40, 80, -1, 0, 1, 41 } };
   const int order[6] = { 0, 1, 2, 2, 3, 0 };
   struct rwa_buffer *verts = rwa_buffer_create(dev, 6 * 48, why, sizeof(why));
   uint8_t *v = rwa_buffer_map(verts);
   memset(v, 0, 6 * 48);
   for (int i = 0; i < 6; i++) {
      const float *q = quad[order[i]];
      float pos[4] = { q[0], q[1], 0, 1 }, a1[2] = { q[2], q[3] }, a2[2] = { q[4], q[5] };
      memcpy(v + i * 48, pos, 16); memcpy(v + i * 48 + 16, a1, 8); memcpy(v + i * 48 + 24, a2, 8);
      for (int k = 0; k < 4; k++) put_half(v + i * 48 + 32 + 2 * k, 1.0f);
   }
   struct rwa_buffer *mvp = rwa_buffer_create(dev, 256, why, sizeof(why)), *tm = rwa_buffer_create(dev, 256, why, sizeof(why));
   const float m[16] = { 1.0f / 128, 0, 0, 0, 0, -1.0f / 128, 0, 0, 0, 0, 0, 0, -1, 1, 0, 1 };
   const float t[8] = { 1, 1, 0, 0, 1.0f / 256, 1.0f / 256, 0, 0 };
   memset(rwa_buffer_map(mvp), 0, 256); memcpy(rwa_buffer_map(mvp), m, sizeof(m));
   memset(rwa_buffer_map(tm), 0, 256); memcpy(rwa_buffer_map(tm), t, sizeof(t));
   struct rwa_buffer *zero[3];
   for (int i = 0; i < 3; i++) { zero[i] = rwa_buffer_create(dev, 256, why, sizeof(why)); memset(rwa_buffer_map(zero[i]), 0, 256); }

   struct rwa_texture_shape ts = { .pixel_format = 80, .type = 2, .width = 256, .height = 256, .depth = 1, .array_length = 1,
                                   .mip_levels = 1, .sample_count = 1, .usage = 5 };
   struct rwa_texture *c0 = rwa_texture_create(dev, &ts, why, sizeof(why)), *c1 = rwa_texture_create(dev, &ts, why, sizeof(why));
   static uint8_t img[256 * 256 * 4];
   unsigned o[3] = { 0, 0, 0 }, sz[3] = { 256, 256, 1 };
   for (int i = 0; i < 256 * 256; i++) { img[i * 4] = 66; img[i * 4 + 1] = 35; img[i * 4 + 2] = 34; img[i * 4 + 3] = 255; }
   rwa_texture_write(c0, 0, 0, o, sz, img, 256 * 4, why, sizeof(why));
   for (int i = 0; i < 256 * 256; i++) { img[i * 4] = img[i * 4 + 1] = img[i * 4 + 2] = 0; img[i * 4 + 3] = (uint8_t)cov_alpha; }
   rwa_texture_write(c1, 0, 0, o, sz, img, 256 * 4, why, sizeof(why));

   struct rwa_buffer *vbufs[4] = { NULL, verts, mvp, tm };
   struct rwa_buffer_bind vt[4] = { { NULL, 0 }, { verts, 0 }, { mvp, 0 }, { tm, 0 } };
   struct rwa_vertex_stream streams[4] = { { NULL, 0 }, { verts, 0 }, { mvp, 0 }, { tm, 0 } };
   struct rwa_texture *colors[2] = { c0, c1 };
   struct rwa_draw dr;
   memset(&dr, 0, sizeof(dr));
   dr.color = colors; dr.color_count = 2;
   dr.vertex = (struct rwa_bindings){ .buffers = vbufs, .buffer_count = 4 };
   dr.fragment = (struct rwa_bindings){ .buffers = zero, .buffer_count = 3 };
   dr.primitive = 3; dr.vertex_count = 6;
   dr.vertex_streams = streams; dr.vertex_stream_count = info.vertex_streams > 4 ? 4 : info.vertex_streams;
   dr.vertex_buffer_table = vt; dr.vertex_buffer_table_count = 4;
   if (rwa_render_draw(r, &dr, why, sizeof(why)) != 0) { printf("draw: %s\n", why); return 1; }
   const unsigned pts[5][2] = { { 40, 40 }, { 44, 44 }, { 52, 52 }, { 60, 60 }, { 79, 79 } };
   for (int k = 0; k < 5; k++) {
      uint8_t p[4] = { 0 };
      unsigned po[3] = { pts[k][0], pts[k][1], 0 }, one[3] = { 1, 1, 1 };
      uint8_t q[4] = { 0 };
      rwa_texture_read(c0, 0, 0, po, one, p, 4, why, sizeof(why));
      rwa_texture_read(c1, 0, 0, po, one, q, 4, why, sizeof(why));
      printf("at (%u,%u): c0 %3u %3u %3u %3u   c1 %3u %3u %3u %3u\n", pts[k][0], pts[k][1], p[0], p[1], p[2], p[3],
             q[0], q[1], q[2], q[3]);
   }
   return 0;
}
