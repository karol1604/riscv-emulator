const std = @import("std");
const Cpu = @import("cpu").Cpu;
const host_mod = @import("host");
const Host = host_mod.Host;
const helpers = @import("helpers.zig");

fn negativeErrno(code: u32) u32 {
    return 0 -% code;
}

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
    var stdin: std.Io.Reader = .fixed("");
    var host = Host.init(std.testing.io, &stdout, &stderr, &stdin);
    const result = try host.run(&cpu, 3);

    switch (result) {
        .exited => |code| try std.testing.expectEqual(@as(u32, 7), code),
        .breakpoint, .fault => return error.UnexpectedRunResult,
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
    var stdin: std.Io.Reader = .fixed("");
    var host = Host.init(std.testing.io, &stdout, &stderr, &stdin);
    const result = try host.run(&cpu, 1);

    switch (result) {
        .breakpoint => {},
        .exited, .fault => return error.UnexpectedRunResult,
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
    var stdin: std.Io.Reader = .fixed("");
    var host = Host.init(std.testing.io, &stdout, &stderr, &stdin);
    try std.testing.expectError(error.InstructionLimitExceeded, host.run(&cpu, 1));
    try std.testing.expectEqual(@as(u32, 1), cpu.regs[1]);
}

test "host runner returns a structured CPU fault" {
    var cpu = Cpu{};
    try helpers.loadWords(&cpu, 0, &.{0xffff_ffff});

    var stdout_buffer: [1]u8 = undefined;
    var stderr_buffer: [1]u8 = undefined;
    var stdout: std.Io.Writer = .fixed(&stdout_buffer);
    var stderr: std.Io.Writer = .fixed(&stderr_buffer);
    var stdin: std.Io.Reader = .fixed("");
    var host = Host.init(std.testing.io, &stdout, &stderr, &stdin);

    switch (try host.run(&cpu, 1)) {
        .fault => |fault| {
            try std.testing.expectEqual(.illegal_instruction, fault.reason);
            try std.testing.expectEqual(@as(u32, 0), fault.pc);
            try std.testing.expectEqual(@as(u32, 0xffff_ffff), fault.value);
        },
        else => return error.ExpectedCpuFault,
    }
    try std.testing.expectEqual(@as(u32, 0), cpu.pc);
}

test "run result formats a structured CPU fault" {
    var buffer: [128]u8 = undefined;
    var writer: std.Io.Writer = .fixed(&buffer);
    const result: host_mod.RunResult = .{
        .fault = .{
            .reason = .load_access_fault,
            .pc = 0x120,
            .value = 0x10003,
        },
    };

    try result.format(&writer);
    try std.testing.expectEqualStrings(
        "Program faulted: load_access_fault at PC=0x00000120, value=0x00010003",
        writer.buffered(),
    );
}

test "write syscall sends guest memory to stdout and stderr" {
    const message = "Hello from guest memory!\n";
    var cpu = Cpu{};
    try cpu.loadProgramAt(0x100, message);

    var stdout_buffer: [64]u8 = undefined;
    var stderr_buffer: [64]u8 = undefined;
    var stdout: std.Io.Writer = .fixed(&stdout_buffer);
    var stderr: std.Io.Writer = .fixed(&stderr_buffer);
    var stdin: std.Io.Reader = .fixed("");
    var host = Host.init(std.testing.io, &stdout, &stderr, &stdin);

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

test "read syscall copies buffered stdin into guest memory and reaches EOF" {
    var cpu = Cpu{};

    var stdout_buffer: [1]u8 = undefined;
    var stderr_buffer: [1]u8 = undefined;
    var stdout: std.Io.Writer = .fixed(&stdout_buffer);
    var stderr: std.Io.Writer = .fixed(&stderr_buffer);
    var stdin: std.Io.Reader = .fixed("hello\n");
    var host = Host.init(std.testing.io, &stdout, &stderr, &stdin);

    const zero_length = try host.handleSyscall(&cpu, .{
        .number = 63,
        .args = .{ 0, 0x100, 0, 0, 0, 0 },
    });
    const first = try host.handleSyscall(&cpu, .{
        .number = 63,
        .args = .{ 0, 0x100, 3, 0, 0, 0 },
    });
    const second = try host.handleSyscall(&cpu, .{
        .number = 63,
        .args = .{ 0, 0x110, 8, 0, 0, 0 },
    });
    const eof = try host.handleSyscall(&cpu, .{
        .number = 63,
        .args = .{ 0, 0x120, 8, 0, 0, 0 },
    });

    try std.testing.expectEqual(@as(u32, 0), zero_length.returned);
    try std.testing.expectEqual(@as(u32, 3), first.returned);
    try std.testing.expectEqual(@as(u32, 3), second.returned);
    try std.testing.expectEqual(@as(u32, 0), eof.returned);
    try std.testing.expectEqualStrings("hel", try cpu.getBytes(0x100, 3));
    try std.testing.expectEqualStrings("lo\n", try cpu.getBytes(0x110, 3));
}

test "read syscall validates the descriptor and guest buffer" {
    var cpu = Cpu{};

    var stdout_buffer: [1]u8 = undefined;
    var stderr_buffer: [1]u8 = undefined;
    var stdout: std.Io.Writer = .fixed(&stdout_buffer);
    var stderr: std.Io.Writer = .fixed(&stderr_buffer);
    var stdin: std.Io.Reader = .fixed("input");
    var host = Host.init(std.testing.io, &stdout, &stderr, &stdin);

    const bad_fd = try host.handleSyscall(&cpu, .{
        .number = 63,
        .args = .{ 1, 0, 1, 0, 0, 0 },
    });
    const bad_address = try host.handleSyscall(&cpu, .{
        .number = 63,
        .args = .{ 0, Cpu.memory_size, 1, 0, 0, 0 },
    });

    try std.testing.expectEqual(@as(u32, 0) -% 9, bad_fd.returned);
    try std.testing.expectEqual(@as(u32, 0) -% 14, bad_address.returned);
}

test "initial stack contains aligned argc argv pointers and null terminator" {
    var cpu = Cpu{};
    try host_mod.prepareInitialStack(&cpu, &.{ "argv-demo.elf", "hello" });

    const stack = try cpu.getBytes(cpu.regs[2], 16);
    const argc = std.mem.readInt(u32, stack[0..4], .little);
    const argv_0 = std.mem.readInt(u32, stack[4..8], .little);
    const argv_1 = std.mem.readInt(u32, stack[8..12], .little);
    const terminator = std.mem.readInt(u32, stack[12..16], .little);

    try std.testing.expectEqual(@as(u32, 0), cpu.regs[2] % 16);
    try std.testing.expectEqual(@as(u32, 2), argc);
    try std.testing.expectEqual(@as(u32, 0), terminator);
    try std.testing.expectEqualStrings("argv-demo.elf\x00", try cpu.getBytes(argv_0, 14));
    try std.testing.expectEqualStrings("hello\x00", try cpu.getBytes(argv_1, 6));
}

test "initial stack rejects more arguments than its address table can hold" {
    var cpu = Cpu{};
    const arguments = [_][]const u8{
        "0", "1", "2", "3", "4", "5", "6", "7", "8", "9", "10",
    };

    try std.testing.expectError(
        error.TooManyArguments,
        host_mod.prepareInitialStack(&cpu, &arguments),
    );
}

test "openat read and close manage a guest file descriptor" {
    var cpu = Cpu{};
    try cpu.loadProgramAt(0x100, "README.md\x00");

    var stdout_buffer: [1]u8 = undefined;
    var stderr_buffer: [1]u8 = undefined;
    var stdout: std.Io.Writer = .fixed(&stdout_buffer);
    var stderr: std.Io.Writer = .fixed(&stderr_buffer);
    var stdin: std.Io.Reader = .fixed("");
    var host = Host.init(std.testing.io, &stdout, &stderr, &stdin);
    defer host.deinit();

    const opened = try host.handleSyscall(&cpu, .{
        .number = 56,
        .args = .{ 0xffff_ff9c, 0x100, 0, 0, 0, 0 },
    });
    const fd = opened.returned;
    try std.testing.expectEqual(@as(u32, 3), fd);

    const read = try host.handleSyscall(&cpu, .{
        .number = 63,
        .args = .{ fd, 0x200, 32, 0, 0, 0 },
    });
    try std.testing.expect(read.returned > 0);
    try std.testing.expectEqualStrings(
        "# RISC-V Emulator",
        try cpu.getBytes(0x200, "# RISC-V Emulator".len),
    );

    const closed = try host.handleSyscall(&cpu, .{
        .number = 57,
        .args = .{ fd, 0, 0, 0, 0, 0 },
    });
    try std.testing.expectEqual(@as(u32, 0), closed.returned);

    const read_after_close = try host.handleSyscall(&cpu, .{
        .number = 63,
        .args = .{ fd, 0x200, 1, 0, 0, 0 },
    });
    try std.testing.expectEqual(negativeErrno(9), read_after_close.returned);
}

test "openat returns specific errors for invalid requests" {
    var cpu = Cpu{};
    try cpu.loadProgramAt(0x100, "this-file-does-not-exist\x00");

    var stdout_buffer: [1]u8 = undefined;
    var stderr_buffer: [1]u8 = undefined;
    var stdout: std.Io.Writer = .fixed(&stdout_buffer);
    var stderr: std.Io.Writer = .fixed(&stderr_buffer);
    var stdin: std.Io.Reader = .fixed("");
    var host = Host.init(std.testing.io, &stdout, &stderr, &stdin);
    defer host.deinit();

    const bad_dirfd = try host.handleSyscall(&cpu, .{
        .number = 56,
        .args = .{ 7, 0x100, 0, 0, 0, 0 },
    });
    const bad_flags = try host.handleSyscall(&cpu, .{
        .number = 56,
        .args = .{ 0xffff_ff9c, 0x100, 1, 0, 0, 0 },
    });
    const missing = try host.handleSyscall(&cpu, .{
        .number = 56,
        .args = .{ 0xffff_ff9c, 0x100, 0, 0, 0, 0 },
    });
    const bad_pointer = try host.handleSyscall(&cpu, .{
        .number = 56,
        .args = .{ 0xffff_ff9c, Cpu.memory_size, 0, 0, 0, 0 },
    });

    @memset(cpu.memory[0x100 .. 0x100 + 4096], 'a');
    const long_path = try host.handleSyscall(&cpu, .{
        .number = 56,
        .args = .{ 0xffff_ff9c, 0x100, 0, 0, 0, 0 },
    });

    try std.testing.expectEqual(negativeErrno(9), bad_dirfd.returned);
    try std.testing.expectEqual(negativeErrno(22), bad_flags.returned);
    try std.testing.expectEqual(negativeErrno(2), missing.returned);
    try std.testing.expectEqual(negativeErrno(14), bad_pointer.returned);
    try std.testing.expectEqual(negativeErrno(36), long_path.returned);
}

test "openat returns EMFILE when the guest descriptor table is full" {
    var cpu = Cpu{};
    try cpu.loadProgramAt(0x100, "README.md\x00");

    var stdout_buffer: [1]u8 = undefined;
    var stderr_buffer: [1]u8 = undefined;
    var stdout: std.Io.Writer = .fixed(&stdout_buffer);
    var stderr: std.Io.Writer = .fixed(&stderr_buffer);
    var stdin: std.Io.Reader = .fixed("");
    var host = Host.init(std.testing.io, &stdout, &stderr, &stdin);
    defer host.deinit();

    for (0..host.file_descriptors.len) |index| {
        const opened = try host.handleSyscall(&cpu, .{
            .number = 56,
            .args = .{ 0xffff_ff9c, 0x100, 0, 0, 0, 0 },
        });
        try std.testing.expectEqual(@as(u32, @intCast(index + 3)), opened.returned);
    }

    const full = try host.handleSyscall(&cpu, .{
        .number = 56,
        .args = .{ 0xffff_ff9c, 0x100, 0, 0, 0, 0 },
    });
    try std.testing.expectEqual(negativeErrno(24), full.returned);
}
