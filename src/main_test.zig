const std = @import("std");
const Cpu = @import("main.zig").Cpu;

fn executeWords(comptime words: []const u32) !Cpu {
    var memory: [words.len * @sizeOf(u32)]u8 = undefined;

    for (words, 0..) |word, i| {
        std.mem.writeInt(u32, memory[i * 4 ..][0..4], word, .little);
    }

    var cpu = Cpu{};
    try cpu.execute(&memory);
    return cpu;
}

test "executes the complete supported instruction program" {
    const cpu = try executeWords(&.{
        0x00c00093, // addi x1,  x0, 12
        0x00500113, // addi x2,  x0, 5
        0x002081b3, // add  x3,  x1, x2
        0x40208233, // sub  x4,  x1, x2
        0x0020f2b3, // and  x5,  x1, x2
        0x00a0f313, // andi x6,  x1, 10
        0x0020e3b3, // or   x7,  x1, x2
        0x00816413, // ori  x8,  x2, 8
        0x0020c4b3, // xor  x9,  x1, x2
        0x00f0c513, // xori x10, x1, 15
        0xfff00593, // addi x11, x0, -1
        0x05a5f613, // andi x12, x11, 0x5a
        0x05506693, // ori  x13, x0, 0x55
        0xfff6c713, // xori x14, x13, -1
        0x00309793, // slli x15, x1, 3
        0x00475813, // srli x16, x14, 4
        0x40475893, // srai x17, x14, 4
        0x00209933, // sll  x18, x1, x2
        0x002759b3, // srl  x19, x14, x2
        0x40275a33, // sra  x20, x14, x2
        0x0015aab3, // slt  x21, x11, x1
        0x0015bb33, // sltu x22, x11, x1
        0x0005ab93, // slti x23, x11, 0
        0xfff03c13, // sltiu x24, x0, -1
    });

    const expected = [_]u32{
        0,
        12,
        5,
        17,
        7,
        4,
        8,
        13,
        13,
        9,
        3,
        0xffff_ffff,
        0x5a,
        0x55,
        0xffff_ffaa,
        96,
        0x0fff_fffa,
        0xffff_fffa,
        384,
        0x07ff_fffd,
        0xffff_fffd,
        1,
        0,
        1,
        1,
    };

    try std.testing.expectEqualSlices(u32, &expected, cpu.regs[0..expected.len]);
    try std.testing.expectEqual(@as(u32, 24 * 4), cpu.pc);
}

test "x0 remains zero and reads as zero" {
    const cpu = try executeWords(&.{
        0x07b00013, // addi x0, x0, 123 (write must be ignored)
        0x00100093, // addi x1, x0, 1
    });

    try std.testing.expectEqual(@as(u32, 0), cpu.regs[0]);
    try std.testing.expectEqual(@as(u32, 1), cpu.regs[1]);
}

test "negative addi immediate is sign extended" {
    const cpu = try executeWords(&.{
        0xfff00093, // addi x1, x0, -1
        0xffe08113, // addi x2, x1, -2
    });

    try std.testing.expectEqual(@as(u32, 0xffff_ffff), cpu.regs[1]);
    try std.testing.expectEqual(@as(u32, 0xffff_fffd), cpu.regs[2]);
}

test "register arithmetic wraps to 32 bits" {
    const cpu = try executeWords(&.{
        0xfff00093, // addi x1, x0, -1
        0x00100113, // addi x2, x0, 1
        0x002081b3, // add  x3, x1, x2 (0xffffffff + 1)
        0x40200233, // sub  x4, x0, x2 (0 - 1)
    });

    try std.testing.expectEqual(@as(u32, 0), cpu.regs[3]);
    try std.testing.expectEqual(@as(u32, 0xffff_ffff), cpu.regs[4]);
}

test "register shifts use only the low five bits of the shift amount" {
    const cpu = try executeWords(&.{
        0xffe00093, // addi x1, x0, -2
        0x02100113, // addi x2, x0, 33
        0x002091b3, // sll  x3, x1, x2
        0x0020d233, // srl  x4, x1, x2
        0x4020d2b3, // sra  x5, x1, x2
    });

    try std.testing.expectEqual(@as(u32, 0xffff_fffc), cpu.regs[3]);
    try std.testing.expectEqual(@as(u32, 0x7fff_ffff), cpu.regs[4]);
    try std.testing.expectEqual(@as(u32, 0xffff_ffff), cpu.regs[5]);
}

test "slli shifts left by an immediate amount" {
    const cpu = try executeWords(&.{
        0x00100093, // addi x1, x0, 1
        0x01f09113, // slli x2, x1, 31
    });

    try std.testing.expectEqual(@as(u32, 0x8000_0000), cpu.regs[2]);
}

test "srli shifts right logically by an immediate amount" {
    const cpu = try executeWords(&.{
        0xfff00093, // addi x1, x0, -1
        0x01f0d113, // srli x2, x1, 31
    });

    try std.testing.expectEqual(@as(u32, 1), cpu.regs[2]);
}

test "srai shifts right arithmetically by an immediate amount" {
    const cpu = try executeWords(&.{
        0xffe00093, // addi x1, x0, -2
        0x4010d113, // srai x2, x1, 1
    });

    try std.testing.expectEqual(@as(u32, 0xffff_ffff), cpu.regs[2]);
}

test "sll shifts left by a register amount" {
    const cpu = try executeWords(&.{
        0x00100093, // addi x1, x0, 1
        0x01f00113, // addi x2, x0, 31
        0x002091b3, // sll  x3, x1, x2
    });

    try std.testing.expectEqual(@as(u32, 0x8000_0000), cpu.regs[3]);
}

test "srl shifts right logically by a register amount" {
    const cpu = try executeWords(&.{
        0xfff00093, // addi x1, x0, -1
        0x01f00113, // addi x2, x0, 31
        0x0020d1b3, // srl  x3, x1, x2
    });

    try std.testing.expectEqual(@as(u32, 1), cpu.regs[3]);
}

test "sra shifts right arithmetically by a register amount" {
    const cpu = try executeWords(&.{
        0xffe00093, // addi x1, x0, -2
        0x00100113, // addi x2, x0, 1
        0x4020d1b3, // sra  x3, x1, x2
    });

    try std.testing.expectEqual(@as(u32, 0xffff_ffff), cpu.regs[3]);
}

test "slt compares registers as signed values" {
    const cpu = try executeWords(&.{
        0xfff00093, // addi x1, x0, -1
        0x00100113, // addi x2, x0, 1
        0x0020a1b3, // slt  x3, x1, x2
        0x00112233, // slt  x4, x2, x1
        0x0010a2b3, // slt  x5, x1, x1
    });

    try std.testing.expectEqual(@as(u32, 1), cpu.regs[3]);
    try std.testing.expectEqual(@as(u32, 0), cpu.regs[4]);
    try std.testing.expectEqual(@as(u32, 0), cpu.regs[5]);
}

test "sltu compares registers as unsigned values" {
    const cpu = try executeWords(&.{
        0xfff00093, // addi x1, x0, -1 (0xffffffff unsigned)
        0x00100113, // addi x2, x0, 1
        0x0020b1b3, // sltu x3, x1, x2
        0x00113233, // sltu x4, x2, x1
        0x0010b2b3, // sltu x5, x1, x1
    });

    try std.testing.expectEqual(@as(u32, 0), cpu.regs[3]);
    try std.testing.expectEqual(@as(u32, 1), cpu.regs[4]);
    try std.testing.expectEqual(@as(u32, 0), cpu.regs[5]);
}

test "slti compares against a sign-extended immediate" {
    const cpu = try executeWords(&.{
        0xfff00093, // addi x1, x0, -1
        0x0000a113, // slti x2, x1, 0
        0xfff02193, // slti x3, x0, -1
    });

    try std.testing.expectEqual(@as(u32, 1), cpu.regs[2]);
    try std.testing.expectEqual(@as(u32, 0), cpu.regs[3]);
}

test "sltiu sign-extends its immediate then compares as unsigned" {
    const cpu = try executeWords(&.{
        0xfff00093, // addi  x1, x0, -1
        0xfff03113, // sltiu x2, x0, -1
        0xfff0b193, // sltiu x3, x1, -1
        0x00103213, // sltiu x4, x0, 1
    });

    try std.testing.expectEqual(@as(u32, 1), cpu.regs[2]);
    try std.testing.expectEqual(@as(u32, 0), cpu.regs[3]);
    try std.testing.expectEqual(@as(u32, 1), cpu.regs[4]);
}

test "incomplete instruction returns OutOfBounds" {
    var cpu = Cpu{};
    const memory = [_]u8{ 0x93, 0x00, 0x50 };

    try std.testing.expectError(error.OutOfBounds, cpu.execute(&memory));
    try std.testing.expectEqual(@as(u32, 0), cpu.pc);
}

test "unsupported opcode is rejected without advancing pc" {
    var cpu = Cpu{};
    const memory = [_]u8{ 0xff, 0xff, 0xff, 0xff };

    try std.testing.expectError(error.UnsupportedOpcode, cpu.execute(&memory));
    try std.testing.expectEqual(@as(u32, 0), cpu.pc);
}

test "unsupported logical funct7 is rejected without advancing pc" {
    var cpu = Cpu{};
    var memory: [4]u8 = undefined;
    std.mem.writeInt(u32, &memory, 0x4020f2b3, .little);

    try std.testing.expectError(error.UnsupportedInstruction, cpu.execute(&memory));
    try std.testing.expectEqual(@as(u32, 0), cpu.pc);
}

test "unsupported shift-immediate funct7 is rejected without advancing pc" {
    var cpu = Cpu{};
    var memory: [4]u8 = undefined;
    std.mem.writeInt(u32, &memory, 0x40109113, .little);

    try std.testing.expectError(error.UnsupportedInstruction, cpu.execute(&memory));
    try std.testing.expectEqual(@as(u32, 0), cpu.pc);
}
