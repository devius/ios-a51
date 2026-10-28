// SPDX-License-Identifier: MIT
// Galaxy S7 port: CoreAnimation settings for backboardd when the shim is in it (on the A51 via DYLD_INSERT_LIBRARIES in
// backboardd's launchd job, tools/a51/sweet-gl-toggle.py; allowed by kernel patch 0146).
// With a GLES context available, iOS 16's render server picked a deep, two-plane display format ('b3a8',
// 10-bit colour plus an alpha plane) that neither this GPU path nor the display driver writes: the panel
// stayed black. As Chlorophyll's backboardd injector does (ry-diffusion/Chlorophyll, inject/, MIT), deep and
// compressed framebuffers and IOSurfaces are turned off before QuartzCore reads its preferences, so the
// display stays 8-bit BGRA.
#include <CoreFoundation/CoreFoundation.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

__attribute__((constructor)) static void hero_backboardd_init(void) {
    if (strcmp(getprogname(), "backboardd") != 0) return;
    setenv("CA_DISABLE_FRAMEBUFFER_COMPRESSION", "1", 1);
    CFPreferencesSetAppValue(CFSTR("CAEnableFramebufferCompression"), kCFBooleanFalse, kCFPreferencesCurrentApplication);
    CFPreferencesSetAppValue(CFSTR("CAEnableIOSurfaceCompression"), kCFBooleanFalse, kCFPreferencesCurrentApplication);
    CFPreferencesSetAppValue(CFSTR("CAEnableDeepFramebuffer"), kCFBooleanFalse, kCFPreferencesCurrentApplication);
    // Galaxy A51 (from the S7 port's notes): the Metal-only material blurs behind Control Center and
    // the dock render black on the GLES path. Reduce Transparency (Accessibility) makes iOS draw
    // those backgrounds solid instead.
    CFPreferencesSetValue(CFSTR("EnhancedBackgroundContrastEnabled"), kCFBooleanTrue,
                          CFSTR("com.apple.Accessibility"), kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
    CFPreferencesSynchronize(CFSTR("com.apple.Accessibility"), kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
}
