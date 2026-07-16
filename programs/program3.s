.section .text.start
.globl _start
.type _start, @function

_start:
    # The CPU has 128 KiB of memory. Start the downward-growing stack at
    # 0x10000, safely above the linked program.
    lui  sp, 0x10

    addi a0, x0, 10
    jal  ra, sum_to

    # sum_to(10) returns 55 in a0.
    ebreak

.size _start, .-_start
