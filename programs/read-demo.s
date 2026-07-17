.option norvc

.section .text.start
.globl _start

_start:
    lui  sp, 0x10
    jal  ra, main

    addi a7, x0, 93
    ecall

.section .text
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
