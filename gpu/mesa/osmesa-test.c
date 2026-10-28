/*
 * First OpenGL on the Galaxy A51's Mali-G72 (from the Galaxy S7 port):
 * OSMesa with the Panfrost screen (gpu/mesa/hero_hw.c) renders a cleared
 * frame with a triangle into memory, checks pixels and times frames.
 *
 *   /private/var/root/gpu/osmesa-test [FRAMES]     (default 300)
 *
 * Run over SSH; the dylibs are in /private/var/root/gpu/lib (rpath). Output
 * goes to stdout and to the kernel log (herodrm_log). HERO_GPU=0 runs on
 * softpipe for comparison. Exit 0 only when the pixels are right and, unless
 * HERO_GPU=0, the renderer is Panfrost: a silent softpipe fallback fails (2),
 * any failed GPU job in the run fails (3), wrong pixels fail (1).
 */
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>
#include <time.h>
#include <unistd.h>

#include <GL/osmesa.h>

void herodrm_log(const char *fmt, ...);
unsigned long long herodrm_fault_count(void);

#include <stdarg.h>

/* stdout and the kernel log. */
static void
say(const char *fmt, ...)
{
   char line[512];
   va_list ap;
   va_start(ap, fmt);
   vsnprintf(line, sizeof(line), fmt, ap);
   va_end(ap);
   printf("%s\n", line);
   fflush(stdout);
   herodrm_log("osmesa-test: %s", line);
}

#define W 256
#define H 256

typedef void (*PFN_V)(void);
typedef void (*PFN_E)(unsigned);
typedef void (*PFN_4F)(float, float, float, float);
typedef void (*PFN_3F)(float, float, float);
typedef void (*PFN_2F)(float, float);
typedef void (*PFN_4I)(int, int, int, int);
typedef const unsigned char *(*PFN_STR)(unsigned);
typedef unsigned (*PFN_ERR)(void);

static PFN_V glFinish_, glEnd_;
static PFN_E glClear_, glBegin_;
static PFN_4F glClearColor_;
static PFN_3F glColor3f_;
static PFN_2F glVertex2f_;
static PFN_4I glViewport_;
static PFN_STR glGetString_;
static PFN_ERR glGetError_;

static double
now_ms(void)
{
   struct timespec ts;
   clock_gettime(CLOCK_MONOTONIC, &ts);
   return ts.tv_sec * 1e3 + ts.tv_nsec / 1e6;
}

static void
frame(float t)
{
   glClearColor_(0.125f, 0.25f, 0.75f, 1.0f);
   glClear_(0x4000 /* GL_COLOR_BUFFER_BIT */);
   glBegin_(0x0004 /* GL_TRIANGLES */);
   glColor3f_(1.0f, 0.0f, 0.0f);
   glVertex2f_(-0.5f + t, -0.5f);
   glColor3f_(1.0f, 0.0f, 0.0f);
   glVertex2f_(0.5f + t, -0.5f);
   glColor3f_(1.0f, 0.0f, 0.0f);
   glVertex2f_(0.0f + t, 0.5f);
   glEnd_();
}

#define LOAD(var, name) \
   var = (__typeof__(var))OSMesaGetProcAddress(name); \
   if (!var) { say("no %s", name); goto out; }

int
main(int argc, char **argv)
{
   int rc = 1;
   int n = argc > 1 ? atoi(argv[1]) : 300;
   const char *hero = getenv("HERO_GPU");
   bool want_gpu = !(hero && strcmp(hero, "0") == 0);
   setenv("MESA_DEBUG", "1", 0);
   say("start, HERO_GPU=%s, %d frames", hero ? hero : "(unset)", n);

   uint32_t *buf = calloc(W * H, 4);
   double t0 = now_ms();
   OSMesaContext ctx = OSMesaCreateContextExt(OSMESA_RGBA, 0, 0, 0, NULL);
   if (!ctx) {
      say("OSMesaCreateContextExt failed");
      goto out;
   }
   if (!OSMesaMakeCurrent(ctx, buf, 0x1401 /* GL_UNSIGNED_BYTE */, W, H)) {
      say("OSMesaMakeCurrent failed");
      goto out;
   }
   say("context in %.1f ms", now_ms() - t0);

   LOAD(glFinish_, "glFinish");
   LOAD(glEnd_, "glEnd");
   LOAD(glClear_, "glClear");
   LOAD(glBegin_, "glBegin");
   LOAD(glClearColor_, "glClearColor");
   LOAD(glColor3f_, "glColor3f");
   LOAD(glVertex2f_, "glVertex2f");
   LOAD(glViewport_, "glViewport");
   LOAD(glGetString_, "glGetString");
   LOAD(glGetError_, "glGetError");

   const char *renderer = (const char *)glGetString_(0x1F01);
   say("GL_RENDERER = %s", renderer ? renderer : "(null)");
   say("GL_VERSION = %s", glGetString_(0x1F02));
   bool on_gpu = renderer && (strcasestr(renderer, "panfrost") || strcasestr(renderer, "mali"));
   if (want_gpu && !on_gpu) {
      say("FAIL: not on the GPU (renderer %s)", renderer ? renderer : "(null)");
      rc = 2;
      goto out;
   }

   glViewport_(0, 0, W, H);
   t0 = now_ms();
   frame(0.0f);
   glFinish_();
   say("first frame in %.1f ms (shader compiles included), GL error 0x%x",
               now_ms() - t0, glGetError_());

   /* OSMesa's buffer is bottom-up; RGBA bytes, so 0xAABBGGRR words. */
   uint32_t center = buf[(H / 2) * W + W / 2], corner = buf[2 * W + 2];
   int red = 0, blue = 0;
   for (int i = 0; i < W * H; i++) {
      unsigned r = buf[i] & 0xff, g = (buf[i] >> 8) & 0xff, b = (buf[i] >> 16) & 0xff;
      red += r > 200 && g < 40 && b < 40;
      blue += b > 150 && r < 60;
   }
   /* The triangle (base 128 px, height 128 px) covers 8192 pixels. */
   bool pixels_ok = red > 7900 && red < 8500 && red + blue == W * H;
   say("pixels %s: center 0x%08x (red 0xff0000ff), corner 0x%08x (blue ~0xffbf4020), "
       "%d red, %d blue of %d", pixels_ok ? "ok" : "FAILED",
       center, corner, red, blue, W * H);

   t0 = now_ms();
   for (int i = 0; i < n; i++) {
      frame((i % 50) / 100.0f);
      glFinish_();
   }
   double ms = now_ms() - t0;
   say("%d frames %dx%d with glFinish: %.1f ms, %.2f ms/frame (%.0f fps) on %s",
       n, W, H, ms, ms / n, n * 1000.0 / ms, on_gpu ? "the GPU" : "softpipe");
   rc = pixels_ok ? 0 : 1;
   if (herodrm_fault_count()) {    /* a failed GPU job anywhere in the run */
      say("FAIL: %llu GPU job(s) failed (kernel log has the status)", herodrm_fault_count());
      rc = 3;
   }

   OSMesaDestroyContext(ctx);
out:
   say("done, exit %d", rc);
   return rc;
}
