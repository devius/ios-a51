/*
 * Copyright 2026 the ios-a51 contributors
 * SPDX-License-Identifier: MIT
 *
 * The two IOSurface calls air_metal.c makes of Bergamota's libdrm stand-in
 * (gpu/freedreno-sweet/sweet_drm.c there), over ours, gpu/mesa/herodrm.c.
 * herodrm_surface_import also hands back a descriptor standing for the BO,
 * which Panfrost imports (WINSYS_HANDLE_TYPE_FD). It is left open: herodrm
 * closes it when the BO is freed (herodrm.c, free_bo), and Panfrost's
 * import in air_metal.c asks herodrm for it directly.
 */
#include <stdint.h>

struct herodrm_surface {
   uint32_t handle, bytes_per_row, width, height, pixel_format, offset, planes;
   uint64_t size;
};
int herodrm_surface_import(uint32_t surface_id, struct herodrm_surface *info);
int herodrm_bo_sync(uint32_t handle);

/* air_metal.c's struct rwa_sbo */
struct rwa_sbo {
   uint32_t surface_id, handle;
   uint64_t size, iova;
   uint32_t offset, bytes_per_row, width, height, pixel_format, planes;
};

int sweet_drm_surface_bo(int fd, struct rwa_sbo *io);
int sweet_drm_surface_bo_prime(struct rwa_sbo *io);
int sweet_drm_bo_sync(int fd, uint32_t handle, uint64_t offset, uint64_t size);

/* The descriptor standing for the BO, or -1. */
int
sweet_drm_surface_bo_prime(struct rwa_sbo *io)
{
   struct herodrm_surface s;
   int prime = herodrm_surface_import(io->surface_id, &s);
   if (prime < 0)
      return -1;
   io->handle = s.handle;
   io->size = s.size;
   io->iova = 0;
   io->offset = s.offset;
   io->bytes_per_row = s.bytes_per_row;
   io->width = s.width;
   io->height = s.height;
   io->pixel_format = s.pixel_format;
   io->planes = s.planes;
   return prime;
}

int
sweet_drm_surface_bo(int fd, struct rwa_sbo *io)
{
   (void)fd;
   return sweet_drm_surface_bo_prime(io) < 0 ? -1 : 0;
}

int
sweet_drm_bo_sync(int fd, uint32_t handle, uint64_t offset, uint64_t size)
{
   (void)fd; (void)offset; (void)size;
   return herodrm_bo_sync(handle);
}
