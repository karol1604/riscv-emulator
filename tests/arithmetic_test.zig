const std = @import("std");
const Cpu = @import("cpu").Cpu;
const helpers = @import("helpers.zig");

const loadWords = helpers.loadWords;
const executeWords = helpers.executeWords;
const encodeBranch = helpers.encodeBranch;
const branchPc = helpers.branchPc;
const encodeJal = helpers.encodeJal;
const encodeJalr = helpers.encodeJalr;

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
        0x10000c93, // addi x25, x0, 256
        0x00eca223, // sw   x14, 4(x25)
        0x004cad03, // lw   x26, 4(x25)
        0xfedcae23, // sw   x13, -4(x25)
        0xffccad83, // lw   x27, -4(x25)
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
        256,
        0xffff_ffaa,
        0x55,
    };

    try std.testing.expectEqualSlices(u32, &expected, cpu.regs[0..expected.len]);
    try std.testing.expectEqualSlices(u8, &.{ 0xaa, 0xff, 0xff, 0xff }, cpu.memory[260..264]);
    try std.testing.expectEqualSlices(u8, &.{ 0x55, 0, 0, 0 }, cpu.memory[252..256]);
    try std.testing.expectEqual(@as(u32, 29 * 4), cpu.pc);
}

test "run executes exactly the requested number of instructions" {
    const words = [_]u32{
        0x00500093, // addi x1, x0, 5
        0x00700113, // addi x2, x0, 7
    };
    var program: [words.len * 4]u8 = undefined;
    for (words, 0..) |word, i| {
        std.mem.writeInt(u32, program[i * 4 ..][0..4], word, .little);
    }

    var cpu = Cpu{};
    try cpu.loadProgramAt(0, &program);

    try cpu.run(1);
    try std.testing.expectEqual(@as(u32, 5), cpu.regs[1]);
    try std.testing.expectEqual(@as(u32, 0), cpu.regs[2]);
    try std.testing.expectEqual(@as(u32, 4), cpu.pc);

    try cpu.run(1);
    try std.testing.expectEqual(@as(u32, 7), cpu.regs[2]);
    try std.testing.expectEqual(@as(u32, 8), cpu.pc);
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

test "sw and lw round-trip a word in little-endian order" {
    const cpu = try executeWords(&.{
        0x10000093, // addi x1, x0, 256
        0xfaa00113, // addi x2, x0, -86
        0x0020a223, // sw   x2, 4(x1)
        0x0040a183, // lw   x3, 4(x1)
    });

    try std.testing.expectEqual(@as(u32, 0xffff_ffaa), cpu.regs[3]);
    try std.testing.expectEqualSlices(
        u8,
        &.{ 0xaa, 0xff, 0xff, 0xff },
        cpu.memory[260..264],
    );
}

test "sw and lw sign-extend a negative offset" {
    const cpu = try executeWords(&.{
        0x10400093, // addi x1, x0, 260
        0x05500113, // addi x2, x0, 0x55
        0xfe20ae23, // sw   x2, -4(x1)
        0xffc0a183, // lw   x3, -4(x1)
    });

    try std.testing.expectEqual(@as(u32, 0x55), cpu.regs[3]);
    try std.testing.expectEqualSlices(u8, &.{ 0x55, 0, 0, 0 }, cpu.memory[256..260]);
}

test "lw targeting x0 does not change x0" {
    const cpu = try executeWords(&.{
        0x10000093, // addi x1, x0, 256
        0x02a00113, // addi x2, x0, 42
        0x0020a023, // sw   x2, 0(x1)
        0x0000a003, // lw   x0, 0(x1)
    });

    try std.testing.expectEqual(@as(u32, 0), cpu.regs[0]);
    try std.testing.expectEqualSlices(u8, &.{ 42, 0, 0, 0 }, cpu.memory[256..260]);
}

test "byte and halfword accesses sign-extend negative offsets" {
    const cpu = try executeWords(&.{
        0x10400093, // addi x1, x0, 260
        0x08000113, // addi x2, x0, 0x80
        0xfe208fa3, // sb   x2, -1(x1)
        0xfff08183, // lb   x3, -1(x1)
        0x00100213, // addi x4, x0, 1
        0x00f21213, // slli x4, x4, 15
        0xfe409e23, // sh   x4, -4(x1)
        0xffc09283, // lh   x5, -4(x1)
    });

    try std.testing.expectEqual(@as(u32, 0xffff_ff80), cpu.regs[3]);
    try std.testing.expectEqual(@as(u32, 0xffff_8000), cpu.regs[5]);
    try std.testing.expectEqual(@as(u8, 0x80), cpu.memory[259]);
    try std.testing.expectEqualSlices(u8, &.{ 0, 0x80 }, cpu.memory[256..258]);
}

test "byte and halfword accesses work at the end of memory" {
    var byte_cpu = Cpu{};
    try loadWords(&byte_cpu, 0, &.{
        0x00208023, // sb  x2, 0(x1)
        0x0000c183, // lbu x3, 0(x1)
    });
    byte_cpu.regs[1] = @intCast(byte_cpu.memory.len - 1);
    byte_cpu.regs[2] = 0xab;
    try byte_cpu.run(2);
    try std.testing.expectEqual(@as(u32, 0xab), byte_cpu.regs[3]);
    try std.testing.expectEqual(@as(u8, 0xab), byte_cpu.memory[byte_cpu.memory.len - 1]);

    var half_cpu = Cpu{};
    try loadWords(&half_cpu, 0, &.{
        0x00209023, // sh  x2, 0(x1)
        0x0000d183, // lhu x3, 0(x1)
    });
    half_cpu.regs[1] = @intCast(half_cpu.memory.len - 2);
    half_cpu.regs[2] = 0xbeef;
    try half_cpu.run(2);
    try std.testing.expectEqual(@as(u32, 0xbeef), half_cpu.regs[3]);
    try std.testing.expectEqualSlices(
        u8,
        &.{ 0xef, 0xbe },
        half_cpu.memory[half_cpu.memory.len - 2 ..],
    );
}

test "unaligned lh lhu and sh fail without advancing pc" {
    var lh_cpu = Cpu{};
    try loadWords(&lh_cpu, 0, &.{0x00009103}); // lh x2, 0(x1)
    lh_cpu.regs[1] = 257;
    try std.testing.expectError(error.UnalignedAccess, lh_cpu.run(1));
    try std.testing.expectEqual(@as(u32, 0), lh_cpu.pc);

    var lhu_cpu = Cpu{};
    try loadWords(&lhu_cpu, 0, &.{0x0000d103}); // lhu x2, 0(x1)
    lhu_cpu.regs[1] = 257;
    try std.testing.expectError(error.UnalignedAccess, lhu_cpu.run(1));
    try std.testing.expectEqual(@as(u32, 0), lhu_cpu.pc);

    var sh_cpu = Cpu{};
    try loadWords(&sh_cpu, 0, &.{0x00209023}); // sh x2, 0(x1)
    sh_cpu.regs[1] = 257;
    sh_cpu.regs[2] = 0xbeef;
    const before = sh_cpu.memory[256..260].*;
    try std.testing.expectError(error.UnalignedAccess, sh_cpu.run(1));
    try std.testing.expectEqual(@as(u32, 0), sh_cpu.pc);
    try std.testing.expectEqualSlices(u8, &before, sh_cpu.memory[256..260]);
}

test "unsupported opcode is rejected without advancing pc" {
    var cpu = Cpu{};
    const program = [_]u8{ 0xff, 0xff, 0xff, 0xff };
    try cpu.loadProgramAt(0, &program);

    try std.testing.expectError(error.UnsupportedOpcode, cpu.run(1));
    try std.testing.expectEqual(@as(u32, 0), cpu.pc);
}

test "unsupported logical funct7 is rejected without advancing pc" {
    var cpu = Cpu{};
    var program: [4]u8 = undefined;
    std.mem.writeInt(u32, &program, 0x4020f2b3, .little);
    try cpu.loadProgramAt(0, &program);

    try std.testing.expectError(error.UnsupportedInstruction, cpu.run(1));
    try std.testing.expectEqual(@as(u32, 0), cpu.pc);
}

test "unsupported shift-immediate funct7 is rejected without advancing pc" {
    var cpu = Cpu{};
    var program: [4]u8 = undefined;
    std.mem.writeInt(u32, &program, 0x40109113, .little);
    try cpu.loadProgramAt(0, &program);

    try std.testing.expectError(error.UnsupportedInstruction, cpu.run(1));
    try std.testing.expectEqual(@as(u32, 0), cpu.pc);
}

test "lui places the immediate in the upper 20 bits" {
    const cpu = try executeWords(&.{
        0x123450b7, // lui x1, 0x12345
        0x80000137, // lui x2, 0x80000
        0xfffff037, // lui x0, 0xfffff (write must be ignored)
    });

    try std.testing.expectEqual(@as(u32, 0x1234_5000), cpu.regs[1]);
    try std.testing.expectEqual(@as(u32, 0x8000_0000), cpu.regs[2]);
    try std.testing.expectEqual(@as(u32, 0), cpu.regs[0]);
}

test "auipc adds the upper immediate to its instruction address" {
    var cpu = Cpu{};
    try loadWords(&cpu, 0x100, &.{
        0x12345097, // auipc x1, 0x12345
        0xfffff117, // auipc x2, 0xfffff
    });
    cpu.pc = 0x100;

    try cpu.run(2);

    try std.testing.expectEqual(@as(u32, 0x1234_5100), cpu.regs[1]);
    try std.testing.expectEqual(@as(u32, 0xffff_f104), cpu.regs[2]);
    try std.testing.expectEqual(@as(u32, 0x108), cpu.pc);
}
