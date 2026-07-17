.option norvc

.section .text.start
.globl _start

_start:
    lw   a0, 0(sp)
    addi a1, sp, 4
    jal  ra, main

    addi a0, x0, 69
    addi a7, x0, 93
    ecall

.section .text
.globl sys_write
sys_write:
    addi a7, x0, 64
    ecall
    jalr x0, 0(ra)
