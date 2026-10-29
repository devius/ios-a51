/*
 * Copyright 2026 the ios-a51 contributors
 * SPDX-License-Identifier: MIT
 *
 * Which part of a render pass fails on the Mali (plan Task 6, diagnostics):
 * four draws of the lower-left triangle on a gray clear, each reporting the
 * pixel inside (16,48), outside (48,16) and how many pixels differ from the
 * clear colour.
 *   a51_render_diag QuartzCore.metallib bg_render.metallib a51_kernels.metallib
 */
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "air_metal.h"

static uint64_t rd64(const uint8_t *p) { uint64_t v = 0; for (int i = 7; i >= 0; i--) v = v << 8 | p[i]; return v; }
static uint32_t rd32(const uint8_t *p) { return p[0] | p[1] << 8 | p[2] << 16 | (uint32_t)p[3] << 24; }
static uint16_t rd16(const uint8_t *p) { return p[0] | p[1] << 8; }

/* bgair_vertex_test.c's reader (Chlorophyll, MIT) */
static const uint8_t *
fn_of(const uint8_t *b, const char *want, size_t *out)
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
   return NULL;
}

static uint8_t *
slurp(const char *path)
{
   FILE *f = fopen(path, "rb");
   if (!f) { perror(path); exit(2); }
   fseek(f, 0, SEEK_END);
   long n = ftell(f);
   rewind(f);
   uint8_t *b = malloc(n);
   if (fread(b, 1, n, f) != (size_t)n) exit(2);
   fclose(f);
   return b;
}

static struct rwa_device *dev;

/* vlib/vfn, flib/ffn: the stages; ca: CoreAnimation's attribute layout */
static void
diag_prim(const char *name, const uint8_t *vlib, const char *vfn, const uint8_t *flib, const char *ffn, int ca,
          unsigned prim, unsigned count);

static void
diag(const char *name, const uint8_t *vlib, const char *vfn, const uint8_t *flib, const char *ffn, int ca)
{
   diag_prim(name, vlib, vfn, flib, ffn, ca, 3, 3);
}

/* prim: MTLPrimitiveType (1 lines, 3 triangles), count: vertices */
static void
diag_prim(const char *name, const uint8_t *vlib, const char *vfn, const uint8_t *flib, const char *ffn, int ca,
          unsigned prim, unsigned count)
{
   char why[512] = { 0 };
   size_t vs, fs;
   const uint8_t *vb = fn_of(vlib, vfn, &vs), *fb = fn_of(flib, ffn, &fs);
   if (!vb || !fb) { printf("%s: functions not found\n", name); return; }
   struct rwa_render_shape shape;
   memset(&shape, 0, sizeof(shape));
   shape.color_format[0] = 80; shape.color_count = 1; shape.sample_count = 1;
   for (int i = 0; i < 8; i++) shape.color_blend[i].write_mask = 0xf;
   shape.color_blend_count = 8;
   if (ca) {
      shape.vertex_attribute[0].format = 31; shape.vertex_attribute[0].offset = 0; shape.vertex_attribute[0].buffer_index = 0;
      shape.vertex_attribute[3].format = 31; shape.vertex_attribute[3].offset = 16; shape.vertex_attribute[3].buffer_index = 0;
      shape.vertex_layout[0].stride = 32; shape.vertex_layout[0].step_function = 1; shape.vertex_layout[0].step_rate = 1;
   }
   struct rwa_render_info info;
   memset(&info, 0, sizeof(info));
   struct rwa_render *r = rwa_render_create(dev, vb, vs, vfn, fb, fs, ffn, &shape, &info, why, sizeof(why));
   if (!r) { printf("%s: rwa_render_create: %s\n", name, why); return; }
   float verts[3 * 8] = { -1, -1, 0, 1,  1, 0, 0, 1,    1, -1, 0, 1,  0, 1, 0, 1,    -1, 1, 0, 1,  0, 0, 1, 1 };
   struct rwa_buffer *vbuf = rwa_buffer_create(dev, sizeof(verts), why, sizeof(why));
   memcpy(rwa_buffer_map(vbuf), verts, sizeof(verts));
   float ident[16] = { 1, 0, 0, 0,  0, 1, 0, 0,  0, 0, 1, 0,  0, 0, 0, 1 };
   struct rwa_buffer *mvp = rwa_buffer_create(dev, 256, why, sizeof(why)), *tm = rwa_buffer_create(dev, 256, why, sizeof(why));
   memset(rwa_buffer_map(mvp), 0, 256); memset(rwa_buffer_map(tm), 0, 256);
   memcpy(rwa_buffer_map(mvp), ident, sizeof(ident)); memcpy(rwa_buffer_map(tm), ident, sizeof(ident));
   struct rwa_texture_shape ts = { .pixel_format = 80, .type = 2, .width = 64, .height = 64, .depth = 1, .array_length = 1, .mip_levels = 1, .sample_count = 1, .usage = 5 };
   struct rwa_texture *rt = rwa_texture_create(dev, &ts, why, sizeof(why));
   struct rwa_buffer *vbufs[4] = { vbuf, NULL, mvp, tm };
   struct rwa_buffer_bind vt[4] = { { vbuf, 0 }, { NULL, 0 }, { mvp, 0 }, { tm, 0 } };
   struct rwa_vertex_stream streams[1] = { { vbuf, 0 } };
   float clear[4] = { 0.25f, 0.25f, 0.25f, 1 };
   struct rwa_texture *colors[1] = { rt };
   struct rwa_draw dr;
   memset(&dr, 0, sizeof(dr));
   dr.color = colors; dr.color_count = 1; dr.clear_color = clear;
   dr.vertex = (struct rwa_bindings){ .buffers = vbufs, .buffer_count = ca ? 4 : 1 };
   dr.primitive = prim; dr.vertex_count = count;
   dr.vertex_streams = streams; dr.vertex_stream_count = info.vertex_streams;
   dr.vertex_buffer_table = vt; dr.vertex_buffer_table_count = ca ? 4 : 1;
   if (rwa_render_draw(r, &dr, why, sizeof(why)) != 0) { printf("%s: draw: %s\n", name, why); return; }
   static uint8_t px[64 * 64 * 4];
   unsigned o[3] = { 0, 0, 0 }, sz[3] = { 64, 64, 1 };
   if (rwa_texture_read(rt, 0, 0, o, sz, px, 64 * 4, why, sizeof(why))) { printf("%s: read: %s\n", name, why); return; }
   unsigned drawn = 0;
   for (int i = 0; i < 64 * 64; i++)
      drawn += px[i * 4] != 64 || px[i * 4 + 1] != 64 || px[i * 4 + 2] != 64;
   const uint8_t *in = px + (48 * 64 + 16) * 4, *out = px + (16 * 64 + 48) * 4;
   printf("%-34s inside %3u,%3u,%3u,%3u  outside %3u,%3u,%3u,%3u  %4u pixels not clear (streams %u)\n", name,
          in[2], in[1], in[0], in[3], out[2], out[1], out[0], out[3], drawn, info.vertex_streams);
}

int
main(int argc, char **argv)
{
   setvbuf(stdout, NULL, _IONBF, 0);
   if (argc < 4) { printf("usage: a51_render_diag QuartzCore.metallib bg_render.metallib a51_kernels.metallib\n"); return 2; }
   uint8_t *qc = slurp(argv[1]), *bg = slurp(argv[2]), *a51 = slurp(argv[3]);
   char why[512] = { 0 };
   dev = rwa_device_open(why, sizeof(why));
   if (!dev) { printf("device: %s\n", why); return 3; }
   printf("(clear is 64,64,64; RGBA)\n");
   diag("1 fixed triangle, solid red", a51, "a51_vs_tri", a51, "a51_fs_red", 0);
   diag("2 bg_vs (buffer) + bg_fs_color", bg, "bg_vs", bg, "bg_fs_color", 0);
   diag("3 std_vert0_lpf + solid red", qc, "std_vert0_lpf", a51, "a51_fs_red", 1);
   diag("4 std_vert0_lpf + bg_fs_ca_color", qc, "std_vert0_lpf", bg, "bg_fs_ca_color", 1);
   /* 5: two 1-pixel lines, ~128 pixels expected (CoreAnimation draws mask coverage as lines) */
   diag_prim("5 line list cross, solid red", a51, "a51_vs_cross", a51, "a51_fs_red", 0, 1, 4);
   return 0;
}
