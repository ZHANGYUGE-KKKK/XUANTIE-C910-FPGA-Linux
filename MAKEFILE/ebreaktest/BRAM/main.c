#define UART_BASE     0x40000000UL
#define UART_TX       (*(volatile unsigned int *)(UART_BASE + 0x04UL))
#define UART_STATUS   (*(volatile unsigned int *)(UART_BASE + 0x08UL))
#define UART_TX_FULL  0x08U

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

int main(void)
{
    uart_puts("\r\n12345,ebreak test,start\r\n");

    __asm__ volatile ("ebreak");

    uart_puts("78910,ebreak continue\r\n");

    while (1) {
        __asm__ volatile ("wfi");
    }
}
