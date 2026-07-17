const std = @import("std");
const Cpu = @import("cpu").Cpu;
const elf = @import("elf.zig");
const host_mod = @import("host.zig");
const Host = host_mod.Host;

const instruction_limit = 10_000_000;

pub fn run(init: std.process.Init) !u8 {
    const io = init.io;
    const allocator = init.arena.allocator();
    const args = try init.minimal.args.toSlice(allocator);

    var stdout_buffer: [4096]u8 = undefined;
    var stderr_buffer: [4096]u8 = undefined;
    var stdin_buffer: [4096]u8 = undefined;

    var stdout = std.Io.File.stdout().writerStreaming(io, &stdout_buffer);
    defer stdout.flush() catch {};

    var stderr = std.Io.File.stderr().writerStreaming(io, &stderr_buffer);
    defer stderr.flush() catch {};

    if (args.len < 2) {
        try stderr.interface.print("Usage: {s} <program.elf> [arguments...]\n", .{args[0]});
        return 2;
    }

    var stdin = std.Io.File.stdin().readerStreaming(io, &stdin_buffer);
    var host = Host.init(&stdout.interface, &stderr.interface, &stdin.interface);

    const elf_path = args[1];
    const elf_data = try elf.loadElf(io, allocator, elf_path);

    var cpu = Cpu{};
    try elf.loadElfIntoCpu(allocator, &cpu, elf_data);

    const guest_args = try allocator.alloc([]const u8, args.len - 1);
    for (args[1..], guest_args) |arg, *guest_arg| {
        guest_arg.* = arg;
    }
    try host_mod.prepareInitialStack(&cpu, guest_args);

    return switch (try host.run(&cpu, instruction_limit)) {
        .exited => |code| @truncate(code),
        .breakpoint => {
            try stderr.interface.writeAll("Guest reached a breakpoint\n");
            return 1;
        },
    };
}
