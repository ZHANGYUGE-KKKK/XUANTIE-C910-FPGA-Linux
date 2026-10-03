#ifndef C910_COREMARK_BOARD_H
#define C910_COREMARK_BOARD_H
#include <stdint.h>
#include <stddef.h>
void board_putc(char c);
void board_puts(const char *s);
void board_hex(uint64_t value);
void board_init(void);
uint64_t board_cycles(void);
uint64_t board_instret(void);
void board_exit(int code) __attribute__((noreturn));
void board_trap(uint64_t cause, uint64_t epc, uint64_t value) __attribute__((noreturn));
extern uint64_t bench_last_cycles, bench_last_instructions;
extern unsigned bench_failed, bench_completed;
extern volatile unsigned long bench_cpu_hz;
#endif
