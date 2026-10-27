/*
 * Display console header for A51 shim
 */

#ifndef DISPLAY_CONSOLE_H
#define DISPLAY_CONSOLE_H

#include <stdint.h>

void draw_diagnostic_screen(void);
void setup_decon_trigger(void);
void trigger_decon_update(void);

#endif