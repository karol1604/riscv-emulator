.option norvc

.section .text.start
.globl _start

_start:
    lw   a0, 0(sp)
    addi a1, sp, 4
    jal  ra, main

    addi a7, x0, 93
    ecall

.section .text
.globl sys_openat
sys_openat:
    addi a7, x0, 56
    ecall
    jalr x0, 0(ra)

.globl sys_close
sys_close:
    addi a7, x0, 57
    ecall
    jalr x0, 0(ra)

.globl sys_read
sys_read:
    addi a7, x0, 63
    ecall
    jalr x0, 0(ra)

.globl sys_write
sys_write:
    addi a7, x0, 64
    ecall
    jalr x0, 0(ra)
