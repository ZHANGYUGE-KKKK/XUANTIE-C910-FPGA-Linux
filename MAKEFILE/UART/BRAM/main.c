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

int main(void)
{
    const char message[] = "HelloWorld!";

    for (const char *p = message; *p != '\0'; ++p) {
        uart_putc(*p);
    }

    while (1) {
        __asm__ volatile ("wfi");
    }
}
