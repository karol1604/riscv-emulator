.section .text.start
.globl _start
.type _start, @function

_start:
    lui  sp, 0x10

    addi a0, x0, 7          # divisor
    addi a1, x0, 12         # input count
    jal  ra, run_workload

    # run_workload(7, 12) should return 0x17e471a4.
    lui  t0, 0x17e47
    addi t0, t0, 0x1a4
    bne  a0, t0, failed

    addi x31, x0, 1
    ebreak

failed:
    addi x31, x0, -1
    ebreak

.size _start, .-_start
