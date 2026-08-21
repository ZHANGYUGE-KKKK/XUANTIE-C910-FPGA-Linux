#define UART_BASE          0x40000000UL
#define UART_TX            (*(volatile unsigned int *)(UART_BASE + 0x04UL))
#define UART_STATUS        (*(volatile unsigned int *)(UART_BASE + 0x08UL))
#define UART_TX_FULL       0x08U

#define OPENSBI_LOAD_ADDR  0x0200000000ULL
#define DTB_LOAD_ADDR      0x0210000000ULL
#define HART_ID            0UL
#define DDR_WAIT_LOOP      1000000UL

typedef void (*opensbi_entry_t)(unsigned long hartid, unsigned long dtb_addr);

static void uart_putc(char c)
{
    while ((UART_STATUS & UART_TX_FULL) != 0U) {
    }

    UART_TX = (unsigned int)c;
}

static void uart_puts(const char *s)
{
    while (*s != '\0') {
        uart_putc(*s);
        ++s;
    }
}

static void wait_for_ddr_ready_time(void)
{
    volatile unsigned long i;

    for (i = 0UL; i < DDR_WAIT_LOOP; ++i) {
        __asm__ volatile ("nop");
    }
}

int main(void)
{
    opensbi_entry_t opensbi_entry = (opensbi_entry_t)OPENSBI_LOAD_ADDR;

    wait_for_ddr_ready_time();
    uart_puts("\r\nLINUX_BOOT_STUB_READY\r\n");

    __asm__ volatile ("ebreak");
    __asm__ volatile ("fence rw, rw" ::: "memory");
    __asm__ volatile ("fence.i");

    uart_puts("JUMP_OPENSBI\r\n");
    opensbi_entry(HART_ID, DTB_LOAD_ADDR);

    while (1) {
        __asm__ volatile ("wfi");
    }
}
