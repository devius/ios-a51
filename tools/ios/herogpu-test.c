/*
 * herogpu-test: the A51's Mali-G72 from user space, through the kernel's
 * HeroGPU service (iokit/Kernel/arm/HeroGPU.cpp, patches 0138-0140). Ported
 * from the Galaxy S7's tools/ios/herogpu-test.c (wardevsa/ios-a5xelte).
 * Run over SSH; output goes to stdout and to the kernel log (HeroGPU Log).
 *
 *   1. GetParam: the Panfrost DRM params Mesa reads first.
 *   2. A WRITE_VALUE job in a buffer of ours, run on JS1.
 *
 * Exit 0 only when GPU_PROD_ID is 0x6221 (Mali-G72) and the job zeroed its
 * canary. The S7's step 3 (a Midgard v5 fragment clear) does not apply to
 * Bifrost and is left out.
 *
 * The iOS SDK has no IOKitLib.h; the few calls used are declared here.
 */
#include <CoreFoundation/CoreFoundation.h>
#include <mach/mach.h>
#include <stdarg.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>

typedef mach_port_t io_object_t;
typedef io_object_t io_service_t;
typedef io_object_t io_connect_t;
CFMutableDictionaryRef IOServiceMatching(const char *name);
io_service_t IOServiceGetMatchingService(mach_port_t mainPort, CFDictionaryRef matching);
kern_return_t IOServiceOpen(io_service_t service, task_port_t owningTask, uint32_t type,
    io_connect_t *connect);
kern_return_t IOServiceClose(io_connect_t connect);
kern_return_t IOObjectRelease(io_object_t object);
kern_return_t IOConnectCallScalarMethod(io_connect_t connection, uint32_t selector,
    const uint64_t *input, uint32_t inputCnt, uint64_t *output, uint32_t *outputCnt);
kern_return_t IOConnectCallStructMethod(io_connect_t connection, uint32_t selector,
    const void *inputStruct, size_t inputStructCnt, void *outputStruct, size_t *outputStructCnt);

enum { GET_PARAM = 0, CREATE_BO = 1, FREE_BO = 2, MAP_BO = 3, SUBMIT = 4, LOG = 5 };

static io_connect_t gpu;

static void
say(const char *fmt, ...)
{
	char line[512];
	va_list ap;
	va_start(ap, fmt);
	int n = vsnprintf(line, sizeof(line), fmt, ap);
	va_end(ap);
	printf("%s\n", line);
	if (gpu != MACH_PORT_NULL && n > 0) {
		IOConnectCallStructMethod(gpu, LOG, line, (size_t)n < sizeof(line) ? (size_t)n : sizeof(line) - 1,
		    NULL, NULL);
	}
}

static kern_return_t
call(uint32_t sel, const uint64_t *in, uint32_t nin, uint64_t *out, uint32_t nout)
{
	uint32_t cnt = nout;
	return IOConnectCallScalarMethod(gpu, sel, in, nin, out, &cnt);
}

struct bo {
	uint64_t handle, va, size;
	volatile uint8_t *cpu;
};

static int
bo_new(struct bo *b, uint64_t size)
{
	uint64_t out[3] = { 0 }, map = 0;
	kern_return_t kr = call(CREATE_BO, &size, 1, out, 3);
	if (kr != KERN_SUCCESS) {
		say("CreateBO(%llu) failed: 0x%x", size, kr);
		return -1;
	}
	b->handle = out[0];
	b->va = out[1];
	b->size = out[2];
	kr = call(MAP_BO, &b->handle, 1, &map, 1);
	if (kr != KERN_SUCCESS || map == 0) {
		say("MapBO(%llu) failed: 0x%x", b->handle, kr);
		return -1;
	}
	b->cpu = (volatile uint8_t *)(uintptr_t)map;
	say("BO %llu: %llu bytes, GPU VA 0x%llx, CPU %p", b->handle, b->size, b->va, (void *)map);
	return 0;
}

static uint32_t
submit(uint64_t jc, unsigned js, uint64_t *us)
{
	uint64_t in[2] = { jc, js }, out[2] = { ~0ull, 0 };
	kern_return_t kr = call(SUBMIT, in, 2, out, 2);
	*us = out[1];
	return kr == KERN_SUCCESS ? (uint32_t)out[0] : 0xdead0000u | (kr & 0xffff);
}

static void
wr32(volatile uint8_t *p, uint32_t off, uint32_t v)
{
	*(volatile uint32_t *)(p + off) = v;
}

static void
wr64(volatile uint8_t *p, uint32_t off, uint64_t v)
{
	*(volatile uint64_t *)(p + off) = v;
}

int
main(void)
{
	io_service_t svc = IOServiceGetMatchingService(MACH_PORT_NULL, IOServiceMatching("HeroGPU"));
	if (svc == MACH_PORT_NULL) {
		printf("no HeroGPU service\n");
		return 1;
	}
	kern_return_t kr = IOServiceOpen(svc, mach_task_self(), 0, &gpu);
	IOObjectRelease(svc);
	if (kr != KERN_SUCCESS) {
		printf("IOServiceOpen: 0x%x\n", kr);
		return 1;
	}
	say("hello from user space, pid %d", getpid());

	/* 1. The params Mesa's panfrost_kmod reads first. */
	static const struct { uint64_t id; const char *name; } params[] = {
		{ 0, "GPU_PROD_ID" }, { 1, "GPU_REVISION" }, { 2, "SHADER_PRESENT" },
		{ 3, "TILER_PRESENT" }, { 6, "AS_PRESENT" }, { 7, "JS_PRESENT" },
		{ 9, "CORE_FEATURES" }, { 10, "TILER_FEATURES" }, { 11, "MEM_FEATURES" },
		{ 12, "MMU_FEATURES" }, { 13, "THREAD_FEATURES" }, { 14, "MAX_THREADS" },
		{ 18, "TEXTURE_FEATURES0" }, { 22, "JS_FEATURES0" },
	};
	uint64_t prod = 0;
	for (unsigned i = 0; i < sizeof(params) / sizeof(params[0]); i++) {
		uint64_t v = 0;
		call(GET_PARAM, &params[i].id, 1, &v, 1);
		say("param %s = 0x%llx", params[i].name, v);
		if (params[i].id == 0) {
			prod = v;
		}
	}
	say("GPU_PROD_ID 0x%llx (%s)", prod, prod == 0x6221 ? "Mali-G72" : "NOT a Mali-G72");

	/* 2. WRITE_VALUE: zero 64 bits over a canary. */
	struct bo job;
	if (bo_new(&job, 0x10000)) {
		return 1;
	}
	wr32(job.cpu, 16, 1 | (2 << 1) | (1u << 16));  /* 64-bit, WRITE_VALUE, index 1 */
	wr64(job.cpu, 32, job.va + 0x100);
	wr64(job.cpu, 40, 3);                           /* zero 64 bits */
	wr64(job.cpu, 0x100, 0xa5a5a5a55a5a5a5aull);
	__asm__ volatile ("dsb sy" ::: "memory");
	uint64_t us = 0;
	uint32_t st = submit(job.va, 1, &us);
	uint64_t v = *(volatile uint64_t *)(job.cpu + 0x100);
	bool ok = st == 0 && v == 0;
	say("write_value %s: status 0x%x, %llu us, output 0x%llx", ok ? "ok" : "FAILED", st, us, v);

	uint64_t hnd = job.handle;
	call(FREE_BO, &hnd, 1, NULL, 0);
	say("done");
	IOServiceClose(gpu);
	return ok && prod == 0x6221 ? 0 : 1;
}
