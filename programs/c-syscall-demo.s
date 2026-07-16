.section .text.start
.globl _start
.type _start, @function

_start:
    lui  sp, 0x10
    jal  ra, main
    addi a0, x0, 69
    addi a7, x0, 93
    ecall

.size _start, .-_start

.section .text
.globl sys_write
.type sys_write, @function

sys_write:
    addi a7, x0, 64
    ecall
    jalr x0, 0(ra)

.size sys_write, .-sys_write
