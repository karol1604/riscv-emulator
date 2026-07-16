const std = @import("std");
const Cpu = @import("cpu").Cpu;
const helpers = @import("helpers.zig");

const loadWords = helpers.loadWords;
const executeWords = helpers.executeWords;
const encodeBranch = helpers.encodeBranch;
const branchPc = helpers.branchPc;
const encodeJal = helpers.encodeJal;
const encodeJalr = helpers.encodeJalr;

test "beq branches only when registers are equal" {
    try std.testing.expectEqual(@as(u32, 8), try branchPc(0b000, 5, 5));
    try std.testing.expectEqual(@as(u32, 4), try branchPc(0b000, 5, 6));
}

test "bne branches only when registers are different" {
    try std.testing.expectEqual(@as(u32, 8), try branchPc(0b001, 5, 6));
    try std.testing.expectEqual(@as(u32, 4), try branchPc(0b001, 5, 5));
}

test "blt compares registers as signed values" {
    try std.testing.expectEqual(@as(u32, 8), try branchPc(0b100, 0xffff_ffff, 1));
    try std.testing.expectEqual(@as(u32, 4), try branchPc(0b100, 1, 0xffff_ffff));
}

test "bge compares registers as signed values" {
    try std.testing.expectEqual(@as(u32, 8), try branchPc(0b101, 1, 0xffff_ffff));
    try std.testing.expectEqual(@as(u32, 4), try branchPc(0b101, 0xffff_ffff, 1));
}

test "bltu compares registers as unsigned values" {
    try std.testing.expectEqual(@as(u32, 8), try branchPc(0b110, 1, 0xffff_ffff));
    try std.testing.expectEqual(@as(u32, 4), try branchPc(0b110, 0xffff_ffff, 1));
}

test "bgeu compares registers as unsigned values" {
    try std.testing.expectEqual(@as(u32, 8), try branchPc(0b111, 0xffff_ffff, 1));
    try std.testing.expectEqual(@as(u32, 4), try branchPc(0b111, 1, 0xffff_ffff));
}

test "taken branch uses a sign-extended PC-relative offset" {
    var cpu = Cpu{};
    try loadWords(&cpu, 4, &.{encodeBranch(0b001, -4)}); // bne x1, x2, -4
    cpu.pc = 4;
    cpu.regs[1] = 1;
    cpu.regs[2] = 2;

    try cpu.runInstructionsForTesting(1);
    try std.testing.expectEqual(@as(u32, 0), cpu.pc);
}

test "misaligned target faults only when branch is taken" {
    var taken = Cpu{};
    try loadWords(&taken, 0, &.{encodeBranch(0b000, 2)});
    taken.regs[1] = 5;
    taken.regs[2] = 5;
    try std.testing.expectError(error.UnalignedAccess, taken.runInstructionsForTesting(1));
    try std.testing.expectEqual(@as(u32, 0), taken.pc);

    var not_taken = Cpu{};
    try loadWords(&not_taken, 0, &.{encodeBranch(0b000, 2)});
    not_taken.regs[1] = 5;
    not_taken.regs[2] = 6;
    try not_taken.runInstructionsForTesting(1);
    try std.testing.expectEqual(@as(u32, 4), not_taken.pc);
}

test "jal writes the return address and jumps PC-relative" {
    var cpu = Cpu{};
    try loadWords(&cpu, 0, &.{encodeJal(5, 8)});

    try cpu.runInstructionsForTesting(1);

    try std.testing.expectEqual(@as(u32, 4), cpu.regs[5]);
    try std.testing.expectEqual(@as(u32, 8), cpu.pc);
}

test "jal sign-extends a negative offset" {
    var cpu = Cpu{};
    try loadWords(&cpu, 8, &.{encodeJal(5, -8)});
    cpu.pc = 8;

    try cpu.runInstructionsForTesting(1);

    try std.testing.expectEqual(@as(u32, 12), cpu.regs[5]);
    try std.testing.expectEqual(@as(u32, 0), cpu.pc);
}

test "jal targeting x0 jumps without changing x0" {
    var cpu = Cpu{};
    try loadWords(&cpu, 0, &.{encodeJal(0, 8)});

    try cpu.runInstructionsForTesting(1);

    try std.testing.expectEqual(@as(u32, 0), cpu.regs[0]);
    try std.testing.expectEqual(@as(u32, 8), cpu.pc);
}

test "misaligned jal target preserves PC and destination register" {
    var cpu = Cpu{};
    try loadWords(&cpu, 0, &.{encodeJal(5, 2)});
    cpu.regs[5] = 0xdead_beef;

    try std.testing.expectError(error.UnalignedAccess, cpu.runInstructionsForTesting(1));
    try std.testing.expectEqual(@as(u32, 0), cpu.pc);
    try std.testing.expectEqual(@as(u32, 0xdead_beef), cpu.regs[5]);
}

test "jalr writes the return address and clears target bit zero" {
    var cpu = Cpu{};
    try loadWords(&cpu, 0, &.{encodeJalr(5, 1, 0)});
    cpu.regs[1] = 9;

    try cpu.runInstructionsForTesting(1);

    try std.testing.expectEqual(@as(u32, 4), cpu.regs[5]);
    try std.testing.expectEqual(@as(u32, 8), cpu.pc);
}

test "jalr sign-extends its immediate" {
    var cpu = Cpu{};
    try loadWords(&cpu, 0, &.{encodeJalr(5, 1, -4)});
    cpu.regs[1] = 12;

    try cpu.runInstructionsForTesting(1);

    try std.testing.expectEqual(@as(u32, 4), cpu.regs[5]);
    try std.testing.expectEqual(@as(u32, 8), cpu.pc);
}

test "jalr reads its base before writing the same register" {
    var cpu = Cpu{};
    try loadWords(&cpu, 0, &.{encodeJalr(1, 1, 0)});
    cpu.regs[1] = 8;

    try cpu.runInstructionsForTesting(1);

    try std.testing.expectEqual(@as(u32, 4), cpu.regs[1]);
    try std.testing.expectEqual(@as(u32, 8), cpu.pc);
}

test "misaligned jalr target preserves PC and destination register" {
    var cpu = Cpu{};
    try loadWords(&cpu, 0, &.{encodeJalr(5, 1, 0)});
    cpu.regs[1] = 6;
    cpu.regs[5] = 0xdead_beef;

    try std.testing.expectError(error.UnalignedAccess, cpu.runInstructionsForTesting(1));
    try std.testing.expectEqual(@as(u32, 0), cpu.pc);
    try std.testing.expectEqual(@as(u32, 0xdead_beef), cpu.regs[5]);
}

test "jalr rejects nonzero funct3" {
    var cpu = Cpu{};
    try loadWords(&cpu, 0, &.{encodeJalr(5, 1, 0) | (@as(u32, 1) << 12)});

    try std.testing.expectError(error.UnsupportedInstruction, cpu.runInstructionsForTesting(1));
    try std.testing.expectEqual(@as(u32, 0), cpu.pc);
}

test "ecall and ebreak require their exact system instruction encodings" {
    inline for ([_]u32{
        0x000000f3, // ecall encoding with rd = x1
        0x00008073, // ecall encoding with rs1 = x1
        0x001000f3, // ebreak encoding with rd = x1
        0x00108073, // ebreak encoding with rs1 = x1
    }) |word| {
        var cpu = Cpu{};
        try loadWords(&cpu, 0, &.{word});
        try std.testing.expectError(
            error.UnsupportedInstruction,
            cpu.runInstructionsForTesting(1),
        );
    }
}
