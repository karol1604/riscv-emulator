.text
.globl _start

_start:
    # Calculate the sum 1 + 2 + ... + 10. Store each partial sum in
    # memory starting at 0x400.
    addi x8,  x0, 0          # sum = 0
    addi x9,  x0, 1          # value = 1
    addi x18, x0, 11         # stop when value reaches 11
    addi x2,  x0, 0x400      # output pointer

sum_loop:
    add  x8, x8, x9          # sum += value
    sw   x8, 0(x2)           # save partial sum
    addi x2, x2, 4           # advance output pointer
    addi x9, x9, 1           # value += 1
    blt  x9, x18, sum_loop

    # Read the final sum back from memory, then call transform(55).
    lw   x10, -4(x2)         # x10 = 55
    addi x11, x10, 0         # preserve the original sum
    jal  x1, transform

    # Verify the function result before doing a few more operations.
    addi x12, x0, 100
    bne  x10, x12, failed

    lui   x5, 0x12345
    xor   x6, x10, x5
    slli  x7, x10, 3
    srli  x13, x5, 4
    srai  x14, x5, 4
    slti  x15, x10, 101
    sltiu x16, x10, -1

    sw   x10, 0(x2)          # store transformed result after partial sums
    addi x17, x0, 1          # success flag
    ebreak

failed:
    addi x17, x0, -1         # failure flag
    ebreak

# transform(n) returns (n << 1) - 10 in x10.
transform:
    slli x10, x10, 1
    addi x10, x10, -10
    jalr x0, 0(x1)
