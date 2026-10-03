.section .text.init
.globl _start
_start:
    csrr t0, mhartid
    bnez t0, 3f
    fence rw, rw
    fence.i
    .option push
    .option norelax
    la gp, __global_pointer$
    la sp, __stack_top
    .option pop
    csrw mie, zero
    csrci mstatus, 8
    # Enter only from a fresh M-mode BRAM loader, never from a running Linux.
    li t0, 0x22000             # MPRV and MPP
    csrc mstatus, t0
    li t0, 0x6000              # FS=Dirty: hardware float/double libc and kernels
    csrs mstatus, t0
    csrw fcsr, zero            # round-to-nearest, clear FP exception flags
    la t0, trap_entry
    csrw mtvec, t0
    la t0, __bss_start
    la t1, __bss_end
1:
    bgeu t0, t1, 2f
    sd zero, 0(t0)
    addi t0, t0, 8
    j 1b
2:
    call main
    mv a0, zero
    call board_exit
3:
    wfi
    j 3b

.balign 4
trap_entry:
    # Switch away from a possibly exhausted/corrupt workload stack.
    la sp, __stack_top
    csrr a0, mcause
    csrr a1, mepc
    csrr a2, mtval
    call board_trap
    j 3b
