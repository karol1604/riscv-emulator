.text
.globl _start

_start:
    addi x1, x0, 0
    addi x2, x0, 10

loop:
    addi x1, x1, 1
    blt  x1, x2, loop

lui  x3, 0x12345
ebreak
