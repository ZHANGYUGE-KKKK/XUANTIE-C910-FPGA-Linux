#define UART_BASE     0x40000000UL
#define UART_TX       (*(volatile unsigned int *)(UART_BASE + 0x04UL))
#define UART_STATUS   (*(volatile unsigned int *)(UART_BASE + 0x08UL))
#define UART_TX_FULL  0x08U

#define DDR_BASE      0x0200000000ULL
#define DDR_TEXT_OFF  0x80ULL
#define DDR_WAIT_LOOP 1000000UL

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

static void uart_put_u64(unsigned long long value)
{
    char buf[20];
    unsigned int i = 0U;

    if (value == 0ULL) {
        uart_putc('0');
        return;
    }

    while (value != 0ULL) {
        buf[i] = (char)('0' + (value % 10ULL));
        value /= 10ULL;
        ++i;
    }

    while (i != 0U) {
        --i;
        uart_putc(buf[i]);
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
    static const unsigned long long write_words[] = {
        1ULL, 2ULL, 3ULL, 4ULL, 5ULL,
        6ULL, 7ULL, 8ULL, 9ULL, 10ULL
    };
    static const char write_text[] = "helloworld from JTAG_DDR";
    volatile unsigned long long *ddr_words = (volatile unsigned long long *)DDR_BASE;
    volatile char *ddr_text = (volatile char *)(DDR_BASE + DDR_TEXT_OFF);
    unsigned int fail = 0U;
    unsigned int i;

    uart_puts("\r\nDDR loopback test start\r\n");
    uart_puts("Wait DDR calibration time...\r\n");
    wait_for_ddr_ready_time();

    for (i = 0U; i < (sizeof(write_words) / sizeof(write_words[0])); ++i) {
        ddr_words[i] = write_words[i];
    }

    for (i = 0U; i < sizeof(write_text); ++i) {
        ddr_text[i] = write_text[i];
    }

    __asm__ volatile ("fence rw, rw" ::: "memory");

    uart_puts("Read numbers: ");
    for (i = 0U; i < (sizeof(write_words) / sizeof(write_words[0])); ++i) {
        unsigned long long value = ddr_words[i];

        if (value != write_words[i]) {
            fail = 1U;
        }

        uart_put_u64(value);
        if (i + 1U != (sizeof(write_words) / sizeof(write_words[0]))) {
            uart_putc(',');
        }
    }

    uart_puts("\r\nRead text: ");
    for (i = 0U; i < sizeof(write_text) - 1U; ++i) {
        char value = ddr_text[i];

        if (value != write_text[i]) {
            fail = 1U;
        }

        uart_putc(value);
    }

    uart_puts("\r\nDDR loopback ");
    uart_puts(fail == 0U ? "PASS\r\n" : "FAIL\r\n");

    while (1) {
        __asm__ volatile ("wfi");
    }
}
