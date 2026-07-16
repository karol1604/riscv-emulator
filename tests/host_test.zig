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

    var stdout_buffer: [1]u8 = undefined;
    var stderr_buffer: [1]u8 = undefined;
    var stdout: std.Io.Writer = .fixed(&stdout_buffer);
    var stderr: std.Io.Writer = .fixed(&stderr_buffer);
    var host = Host.init(&stdout, &stderr);
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

    var stdout_buffer: [1]u8 = undefined;
    var stderr_buffer: [1]u8 = undefined;
    var stdout: std.Io.Writer = .fixed(&stdout_buffer);
    var stderr: std.Io.Writer = .fixed(&stderr_buffer);
    var host = Host.init(&stdout, &stderr);
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

    var stdout_buffer: [1]u8 = undefined;
    var stderr_buffer: [1]u8 = undefined;
    var stdout: std.Io.Writer = .fixed(&stdout_buffer);
    var stderr: std.Io.Writer = .fixed(&stderr_buffer);
    var host = Host.init(&stdout, &stderr);
    try std.testing.expectError(error.InstructionLimitExceeded, host.run(&cpu, 1));
    try std.testing.expectEqual(@as(u32, 1), cpu.regs[1]);
}

test "write syscall sends guest memory to stdout and stderr" {
    const message = "Hello from guest memory!\n";
    var cpu = Cpu{};
    try cpu.loadProgramAt(0x100, message);

    var stdout_buffer: [64]u8 = undefined;
    var stderr_buffer: [64]u8 = undefined;
    var stdout: std.Io.Writer = .fixed(&stdout_buffer);
    var stderr: std.Io.Writer = .fixed(&stderr_buffer);
    var host = Host.init(&stdout, &stderr);

    const stdout_result = try host.handleSyscall(&cpu, .{
        .number = 64,
        .args = .{ 1, 0x100, message.len, 0, 0, 0 },
    });
    const stderr_result = try host.handleSyscall(&cpu, .{
        .number = 64,
        .args = .{ 2, 0x100, message.len, 0, 0, 0 },
    });

    try std.testing.expectEqual(@as(u32, message.len), stdout_result.returned);
    try std.testing.expectEqual(@as(u32, message.len), stderr_result.returned);
    try std.testing.expectEqualStrings(message, stdout.buffered());
    try std.testing.expectEqualStrings(message, stderr.buffered());
}
