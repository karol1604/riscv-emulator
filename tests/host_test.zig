const std = @import("std");
const Cpu = @import("cpu").Cpu;
const Host = @import("host").Host;
const helpers = @import("helpers.zig");

test "exit syscall returns the guest exit status" {
    var cpu = Cpu{};
    try helpers.loadWords(&cpu, 0, &.{
        0x00700513, // addi a0, x0, 7
        0x05d00893, // addi a7, x0, 93
        0x00000073, // ecall
    });

    var host = Host{};
    const result = try host.run(&cpu, 3);

    switch (result) {
        .exited => |code| try std.testing.expectEqual(@as(u32, 7), code),
        .breakpoint => return error.UnexpectedRunResult,
    }
    try std.testing.expectEqual(@as(u32, 12), cpu.pc);
}

test "ebreak returns a breakpoint run result" {
    var cpu = Cpu{};
    try helpers.loadWords(&cpu, 0, &.{0x00100073});

    var host = Host{};
    const result = try host.run(&cpu, 1);

    switch (result) {
        .breakpoint => {},
        .exited => return error.UnexpectedRunResult,
    }
    try std.testing.expectEqual(@as(u32, 4), cpu.pc);
}

test "host runner reports instruction limit exhaustion" {
    var cpu = Cpu{};
    try helpers.loadWords(&cpu, 0, &.{0x00100093}); // addi x1, x0, 1

    var host = Host{};
    try std.testing.expectError(error.InstructionLimitExceeded, host.run(&cpu, 1));
    try std.testing.expectEqual(@as(u32, 1), cpu.regs[1]);
}
