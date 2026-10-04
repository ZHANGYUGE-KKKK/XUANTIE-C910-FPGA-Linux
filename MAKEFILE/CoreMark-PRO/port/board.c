#include "board.h"
#ifdef BENCH_SUITE_PAYLOAD
#include "suite.h"
#endif
#define UART_BASE 0x40000000UL
#define UART_TX (*(volatile unsigned *)(UART_BASE + 4))
#define UART_STATUS (*(volatile unsigned *)(UART_BASE + 8))

void board_putc(char c) {
    if (c == '\n') board_putc('\r');
    while (UART_STATUS & 8U) { }
    UART_TX = (unsigned char)c;
}
void board_puts(const char *s) { while (*s) board_putc(*s++); }
void board_hex(uint64_t v) {
    static const char hex[] = "0123456789abcdef";
    board_puts("0x");
    for (int i = 60; i >= 0; i -= 4) board_putc(hex[(v >> i) & 15]);
}
uint64_t board_cycles(void) {
    uint64_t v;
    __asm__ volatile ("fence rw,rw\ncsrr %0,mcycle" : "=r"(v) :: "memory");
    return v;
}
uint64_t board_instret(void) {
    uint64_t v;
    __asm__ volatile ("csrr %0,minstret" : "=r"(v) :: "memory");
    return v;
}
void board_init(void) {
#ifndef BENCH_SUITE_PAYLOAD
    /* Fresh-reset entry: invalidate I/D tags before enabling the L1 caches.
       MCOR[1:0]=3 selects both caches; MCOR[4]=1 requests invalidate. */
    unsigned long mcor = 0x13;
    __asm__ volatile ("csrw 0x7c2,%0" :: "r"(mcor) : "memory");
    do { __asm__ volatile ("csrr %0,0x7c2" : "=r"(mcor)); } while (mcor & 0x10);
    /* C910 MHCR: I/D cache, write allocation and branch prediction. */
    unsigned long mhcr = 0x11ff, pmdm = 1UL << 13;
    __asm__ volatile ("csrc 0x7f0,%0\ncsrw 0x7c1,%1\nfence.i"
                      :: "r"(pmdm), "r"(mhcr) : "memory");
#endif
    uint64_t before = board_cycles();
    for (volatile unsigned i = 0; i < 1000; ++i) __asm__ volatile ("nop");
    if (board_cycles() <= before) {
        board_puts("ERROR: mcycle is not advancing\n");
        board_exit(1);
    }
}
void board_exit(int code) {
    board_puts(code ? "COREMARK_PRO_FAILED code=" : "COREMARK_PRO_DONE code=");
    board_hex((unsigned)code);
    board_puts("\n");
#ifdef BENCH_SUITE_PAYLOAD
    coremark_suite_finish(code);
#else
    for (;;) __asm__ volatile ("wfi");
#endif
}
void board_trap(uint64_t cause, uint64_t epc, uint64_t value) {
    board_puts("COREMARK_PRO_TRAP mcause="); board_hex(cause);
    board_puts(" mepc="); board_hex(epc);
    board_puts(" mtval="); board_hex(value);
    board_puts("\n");
    board_exit(2);
}
