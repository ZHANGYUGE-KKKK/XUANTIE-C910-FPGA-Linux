/* C910 adaptation of the EEMBC MITH AL. Original workload/harness sources stay intact. */
#include <stdio.h>
#include <stdlib.h>
#include <stdarg.h>
#include "th_lib.h"
#include "th_al.h"
#include "board.h"
static uint64_t start_cycles, start_instructions;
void al_signal_start(void) {
    start_instructions = board_instret();
    start_cycles = board_cycles();
}
size_t al_signal_finished(void) {
    uint64_t end_cycles = board_cycles();
    uint64_t end_instructions = board_instret();
    bench_last_cycles = end_cycles - start_cycles;
    bench_last_instructions = end_instructions - start_instructions;
    return (size_t)bench_last_cycles;
}
size_t al_signal_now(void) { return (size_t)(board_cycles() - start_cycles); }
size_t al_ticks_per_sec(void) { return (size_t)bench_cpu_hz; }
size_t al_tick_granularity(void) { return 1; }
void al_exit(int code) { board_exit(code ? code : 1); }
int al_printf(const char *format, va_list args) { return vprintf(format, args); }
int al_sprintf(char *str, const char *format, va_list args) { return vsprintf(str, format, args); }
int al_write_con(const char *str, size_t size) {
    for (size_t i = 0; i < size; ++i) board_putc(str[i]);
    return Success;
}
int al_vsscanf(const char *str, const char *format, va_list args) { return vsscanf(str, format, args); }
int al_vfscanf(ee_FILE *file, const char *format, va_list args) {
    (void)file; (void)format; (void)args; return EOF;
}
char *al_getenv(const char *name) { (void)name; return NULL; }
void al_main(int argc, char **argv) { (void)argc; (void)argv; }
void al_report_results(void) { }
void al_hardware_reset(int code) { if (code) board_exit(code); }
int al_filecmp(const char *a, const char *b) { (void)a; (void)b; return 0; }
size_t al_fsize(const char *name) { (void)name; return 0; }
void *al_fcreate(const char *name, const char *mode, char *data, size_t size) {
    (void)name; (void)mode; (void)data; (void)size; return NULL;
}
