.section .text.init, "ax", @progbits
.globl _start

_start:
    .option push
    .option norvc
    la   t0, ddr_exec_msg

1:
    lbu  t1, 0(t0)
    beqz t1, 3f

2:
    li   t2, 0x40000008
    lw   t3, 0(t2)
    andi t3, t3, 0x08
    bnez t3, 2b

    li   t2, 0x40000004
    sw   t1, 0(t2)
    addi t0, t0, 1
    j    1b

3:
    wfi
    j    3b
    .option pop

.align 2
ddr_exec_msg:
    .ascii "DDR_EXEC_OK\r\n"
    .byte 0
