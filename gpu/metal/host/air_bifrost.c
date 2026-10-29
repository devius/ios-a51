/*
 * Copyright 2026 the ios-a51 contributors
 * SPDX-License-Identifier: MIT
 *
 * air_bifrost: one function of a .metallib through Chlorophyll's AIR frontend
 * and Panfrost's compiler for one Mali (default G72, gpu id 0x6221), on the
 * host. The NIR takes the path a pipeline of air_metal.c takes on the phone:
 * finalize_for_gallium() (the screen's fs_position_is_sysval is set from
 * Bifrost on), what panfrost_create_shader_state() runs, then what
 * panfrost_shader_compile() runs with a default key. Function constants are all
 * zero, as in Chlorophyll's ir3 tool; their count is reported. A library
 * (air.visible) function is compiled through the frontend's wrapper.
 *
 *   air_bifrost [--gpu-id ID] LIB.metallib [FUNCTION]
 * prints "function=NAME stage=STAGE bytes=N constants=N" and exits 0, or the
 * error and exits 1.
 */
#include <err.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "compiler/air/nir_air.h"
#include "compiler/glsl_types.h"
#include "compiler/nir/nir.h"
#include "pan_context.h"
#include "pan_shader.h"
#include "util/u_dynarray.h"

/* GENX() symbols of the per-arch libraries; this tool builds outside PAN_ARCH. */
#define PAN_PER_ARCH(arch)                                                     \
   const nir_shader_compiler_options *pan_shader_get_compiler_options_v##arch(void); \
   void pan_shader_compile_v##arch(nir_shader *, struct panfrost_compile_inputs *, \
                                   struct util_dynarray *, struct pan_shader_info *);
PAN_PER_ARCH(6)
PAN_PER_ARCH(7)

/* air_metal.c's type_size_vec4 */
static int
type_size_vec4(const struct glsl_type *type, bool bindless)
{
   return glsl_count_attribute_slots(type, false);
}

static void
read_file(const char *path, void **data, size_t *size)
{
   FILE *f = fopen(path, "rb");
   if (!f)
      err(1, "%s", path);
   fseek(f, 0, SEEK_END);
   *size = ftell(f);
   rewind(f);
   *data = malloc(*size);
   if (!*data || fread(*data, 1, *size, f) != *size)
      errx(1, "%s: short read", path);
   fclose(f);
}

static const char *
stage_name(gl_shader_stage s)
{
   switch (s) {
   case MESA_SHADER_VERTEX: return "vertex";
   case MESA_SHADER_FRAGMENT: return "fragment";
   case MESA_SHADER_COMPUTE:
   case MESA_SHADER_KERNEL: return "kernel";
   default: return "other";
   }
}

int
main(int argc, char **argv)
{
   unsigned gpu_id = 0x6221;
   int i = 1;
   if (i + 1 < argc && !strcmp(argv[i], "--gpu-id")) {
      gpu_id = strtoul(argv[i + 1], NULL, 0);
      i += 2;
   }
   if (i >= argc)
      errx(2, "usage: air_bifrost [--gpu-id ID] LIB.metallib [FUNCTION]");
   const char *path = argv[i], *entry = i + 1 < argc ? argv[i + 1] : NULL;
   unsigned arch = pan_arch(gpu_id);
   if (arch != 6 && arch != 7)
      errx(2, "gpu id %#x: only Bifrost (v6, v7) is built in", gpu_id);

   glsl_type_singleton_init_or_ref();

   void *buf;
   size_t size;
   read_file(path, &buf, &size);
   const void *bitcode = buf;
   size_t bitcode_size = size;
   const char *error;
   if (size >= 4 && !memcmp(buf, "MTLB", 4)) {
      struct air_metallib lib;
      if (!air_metallib_parse(NULL, buf, size, &lib, &error))
         errx(1, "%s: %s", path, error);
      unsigned pick = lib.num_functions;
      for (unsigned f = 0; f < lib.num_functions; f++) {
         if (!entry || !strcmp(entry, lib.functions[f].name)) {
            pick = f;
            break;
         }
      }
      if (pick == lib.num_functions)
         errx(1, "%s: no function %s", path, entry ? entry : "(any)");
      bitcode = lib.functions[pick].bitcode;
      bitcode_size = lib.functions[pick].bitcode_size;
      entry = lib.functions[pick].name;
   }

   struct air_constant_value *fc;
   unsigned num_fc = air_module_function_constants(NULL, bitcode, bitcode_size, &fc);
   const struct air_to_nir_options options = {
      .constants = fc,
      .num_constants = num_fc,
      .library_wrapper = true,
   };
   const nir_shader_compiler_options *nir_options =
      arch == 6 ? pan_shader_get_compiler_options_v6() : pan_shader_get_compiler_options_v7();
   struct air_shader_info info;
   nir_shader *nir = air_to_nir(NULL, bitcode, bitcode_size, NULL, &options, nir_options,
                                &info, &error);
   if (!nir)
      errx(1, "%s: %s", entry ? entry : path, error);

   /* A kernel with no fixed threadgroup size is compiled per dispatch, with the size it
    * is dispatched with (air_metal.c's compute_state_for); 32x1x1 stands for one here.
    */
   if (gl_shader_stage_is_compute(nir->info.stage) && nir->info.workgroup_size_variable) {
      nir->info.workgroup_size[0] = 32;
      nir->info.workgroup_size[1] = 1;
      nir->info.workgroup_size[2] = 1;
      nir->info.workgroup_size_variable = false;
   }

   /* finalize_for_gallium (air_metal.c), for a screen with fs_position_is_sysval */
   NIR_PASS(_, nir, nir_lower_system_values);
   static const nir_lower_compute_system_values_options cs_options = { 0 };
   NIR_PASS(_, nir, nir_lower_compute_system_values, &cs_options);
   NIR_PASS(_, nir, nir_lower_io, nir_var_shader_in | nir_var_shader_out,
            type_size_vec4, nir_lower_io_use_interpolated_input_intrinsics);

   /* panfrost_create_shader_state */
   if (nir->info.stage == MESA_SHADER_FRAGMENT &&
       nir->info.outputs_written & BITFIELD_BIT(FRAG_RESULT_COLOR))
      NIR_PASS(_, nir, nir_lower_fragcolor, nir->info.fs.color_is_dual_source ? 1 : 8);
   pan_shader_preprocess(nir, gpu_id);
   if (nir->info.stage == MESA_SHADER_VERTEX)
      NIR_PASS(_, nir, pan_lower_image_index, util_bitcount64(nir->info.inputs_read));

   /* panfrost_shader_compile, default key */
   struct panfrost_compile_inputs inputs = { .gpu_id = gpu_id };
   struct panfrost_sysvals sysvals = { 0 };
   NIR_PASS(_, nir, panfrost_nir_lower_sysvals, arch, &sysvals);
   inputs.pushable_ubos = BITFIELD_BIT(0);
   if (sysvals.sysval_count)
      inputs.pushable_ubos |= BITFIELD_BIT(nir->info.num_ubos - 1);
   NIR_PASS(_, nir, panfrost_nir_lower_res_indices, &inputs);

   struct util_dynarray binary;
   util_dynarray_init(&binary, NULL);
   struct pan_shader_info shader_info = { 0 };
   if (arch == 6)
      pan_shader_compile_v6(nir, &inputs, &binary, &shader_info);
   else
      pan_shader_compile_v7(nir, &inputs, &binary, &shader_info);
   if (!binary.size)
      errx(1, "%s: the compiler produced no code", entry);

   printf("function=%s stage=%s bytes=%u constants=%u\n", entry, stage_name(nir->info.stage),
          binary.size, num_fc);
   return 0;
}
