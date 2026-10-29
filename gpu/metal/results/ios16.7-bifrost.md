# iOS 16.7 shaders through Bifrost (Mali-G72, gpu id 0x6221) — stage 1

2026-10-29. `tools/a51/host/mac-metal-host.sh --md … QuartzCore.metallib CoreImage.metallib`
(iOS 16.7.16 20H392, iPhone10,3; `default.metallib` of each framework; the
`*_bin` archives are AGX machine code and not shaders). Function constants all
zero; a kernel without a fixed threadgroup size compiled at 32x1x1.

## QuartzCore: 132 of 141 compile (hackios, ir3 on iOS 16.5: 135)

| Fails | Functions | Where | Matters? |
|---|---|---|---|
| 4 | `tile_downsample_1/2/4/8` | Bifrost (register format) / frontend (`air.thread_index_in_quadgroup`) | No: tile shaders, requested only when the device reports Apple GPU families above 3; Chlorophyll reports 1–3 |
| 2 | `fixed_frag_lph_cph`, `fixed_frag_lph_cpf` | AIR frontend: program-scope variable initializer not a plain constant | Frontend work (any GPU) |
| 2 | `inplace_copy_lpf`, `inplace_copy_lph` | **Mesa bug**: `nir_divergence_analysis` does not know `load_converted_output_pan`, which Bifrost's framebuffer-fetch lowering emits | Yes: framebuffer reads; small Mesa fix |
| 1 | `compute_apl_fast` | **Bifrost bug**: `bi_pack_add_clper_i32` register assertion (subgroup shuffle on v6) | Probably (APL = average picture level); compiler fix |

Of the 137 functions CoreAnimation can request (no tile shaders), 132 compile.
Spec gate ("far below ir3" → compiler first): not far below; stage 2 goes ahead,
the two Mesa/Bifrost bugs and the frontend case are work items.

## CoreImage: 17 of 58 kernels compile

Most failures are one Bifrost assertion class (`bi_reg_fmt_for_nir`, 41 functions
with the tile kernels): CoreImage filters are not on the home-screen path; a
work item for later.

## Raw output
```
functions=199 reader_ok=199 translate_ok=193 bifrost_ok=149 (gpu id 0x6221)
  CoreImage.metallib                           kernel     total=58   translate=56   bifrost=17
  QuartzCore.metallib                          fragment   total=95   translate=93   bifrost=91
  QuartzCore.metallib                          kernel     total=7    translate=5    bifrost=2
  QuartzCore.metallib                          vertex     total=39   translate=39   bifrost=39
  [41] bifrost: signal N: Assertion failed: (!"..." "..."), function bi_reg_fmt_for_nir, file bifrost_compile.c, line N.   e.g. QuartzCore.metallib/tile_downsample_1, QuartzCore.metallib/tile_downsample_2
  [2] bifrost: signal N: con NxN  %v = @load_converted_output_pan (%v) (dest_type=floatN, io location=N slots=N fbfetch coherent)Assertion failed: (!"..." "..."), function vis   e.g. QuartzCore.metallib/inplace_copy_lpf, QuartzCore.metallib/inplace_copy_lph
  [2] translate: interface: the initializer of a program-scope variable is not a plain constant   e.g. QuartzCore.metallib/fixed_frag_lph_cph, QuartzCore.metallib/fixed_frag_lph_cpf
  [2] translate: interface: input air.thread_index_in_quadgroup   e.g. QuartzCore.metallib/tile_downsample_4, QuartzCore.metallib/tile_downsample_8
  [1] bifrost: signal N: Assertion failed: ((N << srcN) & N), function bi_pack_add_clper_iN, file bi_packer.c, line N.   e.g. QuartzCore.metallib/compute_apl_fast
  [1] translate: instruction: a phi between pointers that name different places, which would have to be chosen at run time   e.g. CoreImage.metallib/kernel_PropagateDisparity
  [1] translate: instruction: a bitcast from N x N bits to N x N bits, which is a repacking this frontend does not do (block N, instruction N, opcode N)   e.g. CoreImage.metallib/convert_rgb8_to_rgba8_buffer
```
