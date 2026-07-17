const std = @import("std");
const Cpu = @import("cpu").Cpu;
const helpers = @import("helpers.zig");

const loadWords = helpers.loadWords;
const executeWords = helpers.executeWords;
const encodeBranch = helpers.encodeBranch;
const branchPc = helpers.branchPc;
const encodeJal = helpers.encodeJal;
const encodeJalr = helpers.encodeJalr;

test "program can be loaded and executed at a nonzero address" {
    var program: [4]u8 = undefined;
    std.mem.writeInt(u32, &program, 0x00700093, .little); // addi x1, x0, 7

    var cpu = Cpu{};
    try cpu.loadProgramAt(16, &program);
    cpu.pc = 16;
    try cpu.runInstructionsForTesting(1);

    try std.testing.expectEqual(@as(u32, 7), cpu.regs[1]);
    try std.testing.expectEqual(@as(u32, 20), cpu.pc);
}

test "out-of-range program load fails without modifying memory" {
    var cpu = Cpu{};
    const program = [_]u8{ 1, 2, 3, 4 };
    const address: u32 = @intCast(cpu.memory.len - 2);

    try std.testing.expectError(error.OutOfBounds, cpu.loadProgramAt(address, &program));
    try std.testing.expectEqualSlices(
        u8,
        &.{ 0, 0 },
        cpu.memory[cpu.memory.len - 2 ..],
    );
}

test "lb sign-extends while lbu zero-extends" {
    const cpu = try executeWords(&.{
        0x10000093, // addi x1, x0, 256
        0x08000113, // addi x2, x0, 0x80
        0x00208023, // sb   x2, 0(x1)
        0x00008183, // lb   x3, 0(x1)
        0x0000c203, // lbu  x4, 0(x1)
    });

    try std.testing.expectEqual(@as(u32, 0xffff_ff80), cpu.regs[3]);
    try std.testing.expectEqual(@as(u32, 0x80), cpu.regs[4]);
}

test "lh sign-extends while lhu zero-extends" {
    const cpu = try executeWords(&.{
        0x10000093, // addi x1, x0, 256
        0x00100113, // addi x2, x0, 1
        0x00f11113, // slli x2, x2, 15
        0x00209023, // sh   x2, 0(x1)
        0x00009183, // lh   x3, 0(x1)
        0x0000d203, // lhu  x4, 0(x1)
    });

    try std.testing.expectEqual(@as(u32, 0xffff_8000), cpu.regs[3]);
    try std.testing.expectEqual(@as(u32, 0x8000), cpu.regs[4]);
}

test "sb stores only the low byte and permits odd addresses" {
    var cpu = Cpu{};
    try loadWords(&cpu, 0, &.{0x00208023}); // sb x2, 0(x1)
    cpu.regs[1] = 257;
    cpu.regs[2] = 0xdead_be80;
    cpu.memory[256..260].* = .{ 0x11, 0x22, 0x33, 0x44 };

    try cpu.runInstructionsForTesting(1);

    try std.testing.expectEqualSlices(
        u8,
        &.{ 0x11, 0x80, 0x33, 0x44 },
        cpu.memory[256..260],
    );
}

test "sh stores only the low halfword in little-endian order" {
    var cpu = Cpu{};
    try loadWords(&cpu, 0, &.{
        0x00209023, // sh  x2, 0(x1)
        0x0000d183, // lhu x3, 0(x1)
    });
    cpu.regs[1] = 256;
    cpu.regs[2] = 0x1234_abcd;
    cpu.memory[256..260].* = .{ 0x11, 0x22, 0x33, 0x44 };

    try cpu.runInstructionsForTesting(2);

    try std.testing.expectEqual(@as(u32, 0xabcd), cpu.regs[3]);
    try std.testing.expectEqualSlices(
        u8,
        &.{ 0xcd, 0xab, 0x33, 0x44 },
        cpu.memory[256..260],
    );
}

test "unaligned lw and sw fail without advancing pc" {
    var load_cpu = Cpu{};
    try loadWords(&load_cpu, 0, &.{
        0x10100093, // addi x1, x0, 257
        0x0000a103, // lw   x2, 0(x1)
    });
    try load_cpu.runInstructionsForTesting(1);
    load_cpu.regs[2] = 0xdead_beef;
    try helpers.expectFault(&load_cpu, .load_address_misaligned, 4, 257);
    try std.testing.expectEqual(@as(u32, 4), load_cpu.pc);
    try std.testing.expectEqual(@as(u32, 0xdead_beef), load_cpu.regs[2]);

    var store_cpu = Cpu{};
    try loadWords(&store_cpu, 0, &.{
        0x10100093, // addi x1, x0, 257
        0x02a00113, // addi x2, x0, 42
        0x0020a023, // sw   x2, 0(x1)
    });
    try store_cpu.runInstructionsForTesting(2);
    try helpers.expectFault(&store_cpu, .store_address_misaligned, 8, 257);
    try std.testing.expectEqual(@as(u32, 8), store_cpu.pc);
    try std.testing.expectEqualSlices(u8, &.{ 0, 0, 0, 0 }, store_cpu.memory[257..261]);
}

test "out-of-bounds lw and sw fail without advancing pc or writing memory" {
    var load_cpu = Cpu{};
    try loadWords(&load_cpu, 0, &.{0x0000a103}); // lw x2, 0(x1)
    load_cpu.regs[1] = @intCast(load_cpu.memory.len);
    load_cpu.regs[2] = 0xdead_beef;
    try helpers.expectFault(
        &load_cpu,
        .load_access_fault,
        0,
        @intCast(load_cpu.memory.len),
    );
    try std.testing.expectEqual(@as(u32, 0), load_cpu.pc);
    try std.testing.expectEqual(@as(u32, 0xdead_beef), load_cpu.regs[2]);

    var store_cpu = Cpu{};
    try loadWords(&store_cpu, 0, &.{0x0020a023}); // sw x2, 0(x1)
    store_cpu.regs[1] = @intCast(store_cpu.memory.len);
    store_cpu.regs[2] = 0xdead_beef;
    const tail_before = store_cpu.memory[store_cpu.memory.len - 4 ..].*;

    try helpers.expectFault(
        &store_cpu,
        .store_access_fault,
        0,
        @intCast(store_cpu.memory.len),
    );
    try std.testing.expectEqual(@as(u32, 0), store_cpu.pc);
    try std.testing.expectEqualSlices(
        u8,
        &tail_before,
        store_cpu.memory[store_cpu.memory.len - 4 ..],
    );
}

test "fetching an instruction beyond memory returns an instruction access fault" {
    var cpu = Cpu{};
    cpu.pc = @intCast(cpu.memory.len - 3);

    const initial_pc = cpu.pc;
    try helpers.expectFault(&cpu, .instruction_access_fault, initial_pc, initial_pc);
    try std.testing.expectEqual(initial_pc, cpu.pc);
}

test "fetching at a misaligned pc returns an instruction address fault" {
    var cpu = Cpu{};
    cpu.pc = 2;

    try helpers.expectFault(&cpu, .instruction_address_misaligned, 2, 2);
    try std.testing.expectEqual(@as(u32, 2), cpu.pc);
}
