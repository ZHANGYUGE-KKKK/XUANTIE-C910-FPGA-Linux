#define UART_BASE 0x40000000UL
#define UART_TX (*(volatile unsigned *)(UART_BASE + 4))
#define UART_STATUS (*(volatile unsigned *)(UART_BASE + 8))
static void puts_uart(const char *s) {
    while (*s) {
        while (UART_STATUS & 8U) { }
        UART_TX = (unsigned char)*s++;
    }
}
int main(void) {
    /* Match LINUX_DDR_execute's startup delay. Confirm MIG calibration on board. */
    for (volatile unsigned i = 0; i < 1000000U; ++i) __asm__ volatile ("nop");
    puts_uart("\r\nCOREMARK_PRO_LOADER_READY\r\n"
              "JTAG: load CoreMark-PRO.elf once; run all 9 workloads.\r\n"
              "Use JTAG/build/load_suite.gdb to start the suite.\r\n"
              "DDR entry=0x200000000; UART=115200 8N1\r\n");
    __asm__ volatile (".globl coremark_loader_break\ncoremark_loader_break:\nebreak");
    /* A generated GDB script selects the DDR ELF entry. Resuming here is an error. */
    puts_uart("COREMARK_PRO_LOADER: select the DDR entry with the GDB script.\r\n");
    for (;;) __asm__ volatile ("wfi");
}
