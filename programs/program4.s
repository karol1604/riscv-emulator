.text
.globl _start

_start:
    # These operands distinguish signed from unsigned high multiplication:
    #   signed:   -2 * -2147483648 =  4294967296
    #   mixed:    -2 *  2147483648 = -4294967296
    addi x1, x0, -2
    lui  x2, 0x80000
    mulh   x3, x1, x2         # expected high half: 0x00000001
    mulhsu x4, x1, x2         # expected high half: 0xffffffff

    # Normal signed and unsigned division using the same register bits.
    addi x10, x0, -20
    addi x11, x0, 3
    div  x5, x10, x11         # -20 / 3 = -6
    rem  x6, x10, x11         # -20 % 3 = -2
    divu x7, x10, x11         # 0xffffffec / 3 = 0x5555554e
    remu x8, x10, x11         # 0xffffffec % 3 = 2

    # RV32M defines division by zero instead of trapping.
    div  x12, x10, x0         # quotient = 0xffffffff
    rem  x13, x10, x0         # remainder = dividend
    divu x14, x10, x0         # quotient = 0xffffffff
    remu x15, x10, x0         # remainder = dividend

    # Signed overflow is also explicitly defined by RV32M.
    addi x16, x0, -1
    div  x17, x2, x16         # INT_MIN / -1 = INT_MIN
    rem  x18, x2, x16         # INT_MIN % -1 = 0

    # Check every result. Any mismatch branches to failed.
    addi x20, x0, 1
    bne  x3, x20, failed

    addi x20, x0, -1
    bne  x4, x20, failed

    addi x20, x0, -6
    bne  x5, x20, failed

    addi x20, x0, -2
    bne  x6, x20, failed

    lui  x20, 0x55555
    addi x20, x20, 0x54e
    bne  x7, x20, failed

    addi x20, x0, 2
    bne  x8, x20, failed

    addi x20, x0, -1
    bne  x12, x20, failed
    bne  x14, x20, failed

    addi x20, x0, -20
    bne  x13, x20, failed
    bne  x15, x20, failed

    bne  x17, x2, failed
    bne  x18, x0, failed

    addi x31, x0, 1
    ebreak

failed:
    addi x31, x0, -1
    ebreak
