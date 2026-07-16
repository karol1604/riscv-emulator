.section .text
.globl _start
.type _start, @function

_start:
    addi a0, x0, 1
    la   a1, stdout_message
    addi a2, x0, 39
    addi a7, x0, 64
    ecall

    addi a0, x0, 2
    la   a1, stderr_message
    addi a2, x0, 39
    addi a7, x0, 64
    ecall

    addi a0, x0, 16
    addi a7, x0, 93
    ecall

stdout_message:
    .ascii "Hello from the RISC-V guest on stdout!\n"
stdout_message_end:

stderr_message:
    .ascii "Hello from the RISC-V guest on stderr!\n"
stderr_message_end:

.size _start, .-_start
