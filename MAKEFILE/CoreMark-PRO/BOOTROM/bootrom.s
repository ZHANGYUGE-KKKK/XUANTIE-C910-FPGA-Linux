.section .text.init
.globl _start
_start:
    .option push
    .option rvc

    la   t0, bootrom_trap
    csrw mtvec, t0

    lui  t0, 0x10
    fence.i
    jalr zero, 0(t0)

.align 2
bootrom_trap:
    csrr t0, mcause
    csrr t1, mtval
1:
    wfi
    j 1b
    .option pop
