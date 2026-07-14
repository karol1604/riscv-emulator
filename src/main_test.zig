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

test "executes a simple program" {
    const cpu = try executeWords(&.{
        0x00500093, // addi x1, x0, 5
        0x00708113, // addi x2, x1, 7
        0x002081b3, // add  x3, x1, x2
        0x40118233, // sub  x4, x3, x1
    });

    try std.testing.expectEqual(@as(u32, 5), cpu.regs[1]);
    try std.testing.expectEqual(@as(u32, 12), cpu.regs[2]);
    try std.testing.expectEqual(@as(u32, 17), cpu.regs[3]);
    try std.testing.expectEqual(@as(u32, 12), cpu.regs[4]);
    try std.testing.expectEqual(@as(u32, 16), cpu.pc);
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
