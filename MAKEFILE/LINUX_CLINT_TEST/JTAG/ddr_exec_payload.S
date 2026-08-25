.section .text.init, "ax", @progbits
.globl _start

.equ UART_TX,       0x40000004
.equ UART_STATUS,   0x40000008
.equ UART_TX_FULL,  0x08

.equ CLINT_MTIMECMP_LO, 0x0c004000
.equ CLINT_MTIMECMP_HI, 0x0c004004
.equ CLINT_MTIME_LO,    0x0c00bff8
.equ CLINT_MTIME_HI,    0x0c00bffc
.equ MTIP_MASK,         0x80
.equ MSTATUS_MIE,       0x8
.equ TIMER_DELTA,       0x00100000
.equ WAIT_LIMIT,        0x01000000

_start:
    .option push
    .option norvc

    la   t0, trap_handler
    csrw mtvec, t0

    la   a0, msg_start
    call uart_puts

    call fixed_write_read_test
    call mtime_delta_test
    call wait_mtip_test

    la   a0, msg_done
    call uart_puts
    j    hang

fixed_write_read_test:
    addi sp, sp, -16
    sd   ra, 8(sp)

    la   a0, msg_fixed_start
    call uart_puts

    li   t0, CLINT_MTIMECMP_LO
    li   t1, 0x11223344
    sw   t1, 0(t0)
    fence rw, rw

    li   t0, CLINT_MTIMECMP_HI
    li   t1, 0x55667788
    sw   t1, 0(t0)
    fence rw, rw

    li   t0, CLINT_MTIMECMP_LO
    lw   t2, 0(t0)
    la   a0, msg_cmp_lo
    call uart_puts
    mv   a0, t2
    call uart_puthex64
    call uart_newline

    li   t0, CLINT_MTIMECMP_HI
    lw   t2, 0(t0)
    la   a0, msg_cmp_hi
    call uart_puts
    mv   a0, t2
    call uart_puthex64
    call uart_newline

    ld   ra, 8(sp)
    addi sp, sp, 16
    ret

mtime_delta_test:
    addi sp, sp, -32
    sd   ra, 24(sp)
    sd   s0, 16(sp)
    sd   s1, 8(sp)

    la   a0, msg_delta_start
    call uart_puts

    li   t0, CLINT_MTIME_LO
    lw   s0, 0(t0)
    li   t0, CLINT_MTIME_HI
    lw   s1, 0(t0)

    la   a0, msg_mtime_lo
    call uart_puts
    mv   a0, s0
    call uart_puthex64
    call uart_newline

    la   a0, msg_mtime_hi
    call uart_puts
    mv   a0, s1
    call uart_puthex64
    call uart_newline

    li   t0, TIMER_DELTA
    add  t1, s0, t0
    sltu t2, t1, s0
    add  t3, s1, t2

    li   t0, CLINT_MTIMECMP_LO
    sw   t1, 0(t0)
    fence rw, rw

    li   t0, CLINT_MTIMECMP_HI
    sw   t3, 0(t0)
    fence rw, rw

    li   t0, CLINT_MTIMECMP_LO
    lw   t4, 0(t0)
    la   a0, msg_next_lo
    call uart_puts
    mv   a0, t4
    call uart_puthex64
    call uart_newline

    li   t0, CLINT_MTIMECMP_HI
    lw   t4, 0(t0)
    la   a0, msg_next_hi
    call uart_puts
    mv   a0, t4
    call uart_puthex64
    call uart_newline

    ld   s1, 8(sp)
    ld   s0, 16(sp)
    ld   ra, 24(sp)
    addi sp, sp, 32
    ret

wait_mtip_test:
    addi sp, sp, -32
    sd   ra, 24(sp)
    sd   s0, 16(sp)

    la   a0, msg_wait_start
    call uart_puts

    li   t0, MTIP_MASK
    csrc mip, t0
    csrs mie, t0

    li   s0, WAIT_LIMIT
1:
    csrr t1, mip
    andi t2, t1, MTIP_MASK
    bnez t2, 2f
    addi s0, s0, -1
    bnez s0, 1b

    la   a0, msg_mtip_timeout
    call uart_puts
    csrr a0, mip
    call uart_puthex64
    call uart_newline
    j    3f

2:
    la   a0, msg_mtip_ok
    call uart_puts
    csrr a0, mip
    call uart_puthex64
    call uart_newline

3:
    li   t0, MTIP_MASK
    csrc mie, t0

    ld   s0, 16(sp)
    ld   ra, 24(sp)
    addi sp, sp, 32
    ret

trap_handler:
    csrr s1, mcause
    csrr s2, mepc
    csrr s3, mtval

    la   a0, msg_trap
    call uart_puts

    la   a0, msg_mcause
    call uart_puts
    mv   a0, s1
    call uart_puthex64
    call uart_newline

    la   a0, msg_mepc
    call uart_puts
    mv   a0, s2
    call uart_puthex64
    call uart_newline

    la   a0, msg_mtval
    call uart_puts
    mv   a0, s3
    call uart_puthex64
    call uart_newline
    j    hang

uart_puts:
    addi sp, sp, -16
    sd   ra, 8(sp)
    sd   s0, 0(sp)
    mv   s0, a0
1:
    lbu  a0, 0(s0)
    beqz a0, 2f
    call uart_putc
    addi s0, s0, 1
    j    1b
2:
    ld   s0, 0(sp)
    ld   ra, 8(sp)
    addi sp, sp, 16
    ret

uart_putc:
    li   t5, UART_STATUS
1:
    lw   t6, 0(t5)
    andi t6, t6, UART_TX_FULL
    bnez t6, 1b
    li   t5, UART_TX
    sw   a0, 0(t5)
    ret

uart_newline:
    addi sp, sp, -16
    sd   ra, 8(sp)
    li   a0, '\r'
    call uart_putc
    li   a0, '\n'
    call uart_putc
    ld   ra, 8(sp)
    addi sp, sp, 16
    ret

uart_puthex64:
    addi sp, sp, -32
    sd   ra, 24(sp)
    sd   s0, 16(sp)
    sd   s1, 8(sp)
    mv   s0, a0

    li   a0, '0'
    call uart_putc
    li   a0, 'x'
    call uart_putc

    li   s1, 60
1:
    srl  t0, s0, s1
    andi t0, t0, 0xf
    li   t1, 10
    bltu t0, t1, 2f
    addi a0, t0, 87
    j    3f
2:
    addi a0, t0, 48
3:
    call uart_putc
    addi s1, s1, -4
    bgez s1, 1b

    ld   s1, 8(sp)
    ld   s0, 16(sp)
    ld   ra, 24(sp)
    addi sp, sp, 32
    ret

hang:
    wfi
    j    hang

.align 3
msg_start:
    .ascii "\r\nCLINT_TEST_START\r\n"
    .byte 0
msg_fixed_start:
    .ascii "FIXED_WRITE_READ_START\r\n"
    .byte 0
msg_cmp_lo:
    .ascii "MTIMECMP_LO="
    .byte 0
msg_cmp_hi:
    .ascii "MTIMECMP_HI="
    .byte 0
msg_delta_start:
    .ascii "MTIME_DELTA_START\r\n"
    .byte 0
msg_mtime_lo:
    .ascii "MTIME_LO="
    .byte 0
msg_mtime_hi:
    .ascii "MTIME_HI="
    .byte 0
msg_next_lo:
    .ascii "NEXT_LO_READBACK="
    .byte 0
msg_next_hi:
    .ascii "NEXT_HI_READBACK="
    .byte 0
msg_wait_start:
    .ascii "WAIT_MTIP_START\r\n"
    .byte 0
msg_mtip_ok:
    .ascii "MTIP_OK mip="
    .byte 0
msg_mtip_timeout:
    .ascii "MTIP_TIMEOUT mip="
    .byte 0
msg_done:
    .ascii "CLINT_TEST_DONE\r\n"
    .byte 0
msg_trap:
    .ascii "CLINT_TRAP\r\n"
    .byte 0
msg_mcause:
    .ascii "mcause="
    .byte 0
msg_mepc:
    .ascii "mepc="
    .byte 0
msg_mtval:
    .ascii "mtval="
    .byte 0

    .option pop
