.section .text.init, "ax", @progbits
.globl _start

.equ UART_TX,       0x40000004
.equ UART_STATUS,   0x40000008
.equ UART_TX_FULL,  0x08
.equ DDR_AMO_ADDR,  0x0200100000

_start:
    .option push
    .option norvc

    la   t0, trap_handler
    csrw mtvec, t0

    la   a0, msg_start
    call uart_puts

    li   s0, DDR_AMO_ADDR
    li   t0, 0x12345678
    sw   t0, 0(s0)
    fence rw, rw
    lw   t1, 0(s0)
    bne  t1, t0, sw_lw_fail

    la   a0, msg_sw_lw_ok
    call uart_puts

    la   a0, msg_before_swap
    call uart_puts

    li   t2, 0
    amoswap.w.aqrl t3, t2, (s0)
    fence rw, rw

    la   a0, msg_swap_old
    call uart_puts
    mv   a0, t3
    call uart_puthex64
    call uart_newline

    lw   t4, 0(s0)
    la   a0, msg_swap_mem
    call uart_puts
    mv   a0, t4
    call uart_puthex64
    call uart_newline

    li   t0, 5
    sw   t0, 0(s0)
    fence rw, rw

    la   a0, msg_before_add
    call uart_puts

    li   t1, 7
    amoadd.w.aqrl t2, t1, (s0)
    fence rw, rw

    la   a0, msg_add_old
    call uart_puts
    mv   a0, t2
    call uart_puthex64
    call uart_newline

    lw   t3, 0(s0)
    la   a0, msg_add_mem
    call uart_puts
    mv   a0, t3
    call uart_puthex64
    call uart_newline

    la   a0, msg_done
    call uart_puts
    j    hang

sw_lw_fail:
    la   a0, msg_sw_lw_fail
    call uart_puts
    la   a0, msg_value
    call uart_puts
    mv   a0, t1
    call uart_puthex64
    call uart_newline
    j    hang

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
    .ascii "\r\nAMO_TEST_START\r\n"
    .byte 0
msg_sw_lw_ok:
    .ascii "SW_LW_OK\r\n"
    .byte 0
msg_sw_lw_fail:
    .ascii "SW_LW_FAIL\r\n"
    .byte 0
msg_before_swap:
    .ascii "BEFORE_AMOSWAP\r\n"
    .byte 0
msg_swap_old:
    .ascii "AMOSWAP_OLD="
    .byte 0
msg_swap_mem:
    .ascii "AMOSWAP_MEM="
    .byte 0
msg_before_add:
    .ascii "BEFORE_AMOADD\r\n"
    .byte 0
msg_add_old:
    .ascii "AMOADD_OLD="
    .byte 0
msg_add_mem:
    .ascii "AMOADD_MEM="
    .byte 0
msg_done:
    .ascii "AMO_TEST_DONE\r\n"
    .byte 0
msg_trap:
    .ascii "AMO_TRAP\r\n"
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
msg_value:
    .ascii "value="
    .byte 0

    .option pop
