const std = @import("std");
const cpu_mod = @import("cpu");
const Cpu = cpu_mod.Cpu;

pub fn expectFault(
    cpu: *Cpu,
    expected_reason: cpu_mod.FaultReason,
    expected_pc: u32,
    expected_value: u32,
) !void {
    switch (try cpu.step()) {
        .fault => |fault| {
            try std.testing.expectEqual(expected_reason, fault.reason);
            try std.testing.expectEqual(expected_pc, fault.pc);
            try std.testing.expectEqual(expected_value, fault.value);
        },
        else => return error.ExpectedCpuFault,
    }
}

pub fn loadWords(cpu: *Cpu, address: u32, comptime words: []const u32) !void {
    var program: [words.len * @sizeOf(u32)]u8 = undefined;

    for (words, 0..) |word, i| {
        std.mem.writeInt(u32, program[i * 4 ..][0..4], word, .little);
    }

    try cpu.loadProgramAt(address, &program);
}

pub fn executeWords(comptime words: []const u32) !Cpu {
    var cpu = Cpu{};
    try loadWords(&cpu, 0, words);
    try cpu.runInstructionsForTesting(words.len);
    return cpu;
}

pub fn encodeBranch(comptime funct3: u3, comptime offset: i13) u32 {
    const imm: u13 = @bitCast(offset);
    return 0b1100011 |
        (@as(u32, (imm >> 11) & 0x1) << 7) |
        (@as(u32, (imm >> 1) & 0xf) << 8) |
        (@as(u32, funct3) << 12) |
        (@as(u32, 1) << 15) |
        (@as(u32, 2) << 20) |
        (@as(u32, (imm >> 5) & 0x3f) << 25) |
        (@as(u32, (imm >> 12) & 0x1) << 31);
}

pub fn branchPc(comptime funct3: u3, lhs: u32, rhs: u32) !u32 {
    var cpu = Cpu{};
    try loadWords(&cpu, 0, &.{encodeBranch(funct3, 8)});
    cpu.regs[1] = lhs;
    cpu.regs[2] = rhs;
    try cpu.runInstructionsForTesting(1);
    return cpu.pc;
}

pub fn encodeJal(comptime rd: u5, comptime offset: i21) u32 {
    const imm: u21 = @bitCast(offset);
    return 0b1101111 |
        (@as(u32, rd) << 7) |
        (@as(u32, (imm >> 12) & 0xff) << 12) |
        (@as(u32, (imm >> 11) & 0x1) << 20) |
        (@as(u32, (imm >> 1) & 0x3ff) << 21) |
        (@as(u32, (imm >> 20) & 0x1) << 31);
}

pub fn encodeJalr(comptime rd: u5, comptime rs1: u5, comptime offset: i12) u32 {
    const imm: u12 = @bitCast(offset);
    return (@as(u32, imm) << 20) |
        (@as(u32, rs1) << 15) |
        (@as(u32, rd) << 7) |
        0b1100111;
}

pub fn encodeM(comptime funct3: u3, comptime rd: u5, comptime rs1: u5, comptime rs2: u5) u32 {
    return (@as(u32, 0b0000001) << 25) |
        (@as(u32, rs2) << 20) |
        (@as(u32, rs1) << 15) |
        (@as(u32, funct3) << 12) |
        (@as(u32, rd) << 7) |
        0b0110011;
}
