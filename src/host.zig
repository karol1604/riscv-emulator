const std = @import("std");
const cpu_mod = @import("cpu");
const Cpu = cpu_mod.Cpu;
const SyscallRequest = cpu_mod.SyscallRequest;

pub const SyscallResult = union(enum) {
    returned: u32,
    exited: u32,
};

pub const RunResult = union(enum) {
    exited: u32,
    breakpoint,

    pub fn format(self: RunResult, writer: *std.Io.Writer) !void {
        switch (self) {
            .exited => |code| try writer.print("Program exited with code {d}", .{code}),
            .breakpoint => try writer.print("Breakpoint reached", .{}),
        }
    }
};

const Syscall = enum(u32) {
    READ = 63,
    WRITE = 64,
    EXIT = 93,
    EXIT_GROUP = 94,
    _,
};

const ErrorCode = enum(u32) {
    EBADF = 9,
    EFAULT = 14,
    ENOSYS = 38,
};

fn errno(code: ErrorCode) u32 {
    return 0 -% @intFromEnum(code);
}

pub const Host = struct {
    stdout: *std.Io.Writer,
    stderr: *std.Io.Writer,
    stdin: *std.Io.Reader,

    pub fn init(stdout: *std.Io.Writer, stderr: *std.Io.Writer, stdin: *std.Io.Reader) Host {
        return .{
            .stdout = stdout,
            .stderr = stderr,
            .stdin = stdin,
        };
    }

    pub fn run(self: *Host, cpu: *Cpu, instr_limit: usize) !RunResult {
        for (0..instr_limit) |_| {
            switch (try cpu.step()) {
                .running => continue,
                .syscall => |request| switch (try self.handleSyscall(cpu, request)) {
                    .returned => |value| cpu.regs[10] = value,
                    .exited => |code| return .{ .exited = code },
                },
                .breakpoint => return .{ .breakpoint = {} },
            }
        }

        return error.InstructionLimitExceeded;
    }

    fn readIntoGuest(reader: *std.Io.Reader, guest_buffer: []u8) !usize {
        if (guest_buffer.len == 0) {
            return 0;
        }

        while (reader.bufferedLen() == 0) {
            reader.fillMore() catch |err| switch (err) {
                error.EndOfStream => return 0,
                error.ReadFailed => return err,
            };
        }

        const available = reader.buffered();
        const count = @min(guest_buffer.len, available.len);

        @memcpy(guest_buffer[0..count], available[0..count]);
        reader.toss(count);

        return count;
    }

    pub fn handleSyscall(self: *Host, cpu: *Cpu, request: SyscallRequest) !SyscallResult {
        const sc: Syscall = @enumFromInt(request.number);
        switch (sc) {
            .READ => {
                const fd = request.args[0];
                const addr = request.args[1];
                const len = request.args[2];

                const reader = switch (fd) {
                    0 => self.stdin,
                    else => return .{ .returned = errno(.EBADF) },
                };

                const cpu_buffer = cpu.getBytesMut(addr, len) catch {
                    return .{ .returned = errno(.EFAULT) };
                };

                const bytes_read = try readIntoGuest(reader, cpu_buffer);

                return .{ .returned = @intCast(bytes_read) };
            },
            .WRITE => {
                const fd = request.args[0];
                const addr = request.args[1];
                const len = request.args[2];
                const writer = switch (fd) {
                    1 => self.stdout,
                    2 => self.stderr,
                    else => return .{ .returned = errno(.EBADF) },
                };
                const bytes = cpu.getBytes(addr, len) catch {
                    return .{ .returned = errno(.EFAULT) };
                };
                try writer.writeAll(bytes);
                try writer.flush();

                return .{ .returned = len };
            },
            .EXIT, .EXIT_GROUP => return .{ .exited = request.args[0] }, // exit, exit_group
            else => {
                std.log.err("Syscall number {d} not implemented\n", .{request.number});
                return .{ .returned = errno(.ENOSYS) };
            },
        }
    }
};

pub fn prepareInitialStack(cpu: *Cpu, argv: []const []const u8) !void {
    var cursor = cpu.memory.len;

    // FIXME: dynamically allocate addresses array based on argv.len
    var addresses: [10]u32 = undefined;
    if (argv.len > addresses.len) return error.TooManyArguments;

    for (0..argv.len) |i| {
        const arg = argv[argv.len - i - 1]; // reverse order
        const arg_len = arg.len + 1; // +1 for null terminator
        if (arg_len > cursor) return error.StackOverflow;
        cursor -= arg_len;
        @memcpy(cpu.memory[cursor..][0..arg.len], arg);
        cpu.memory[cursor + arg.len] = 0; // null terminator
        addresses[argv.len - i - 1] = @intCast(cursor);
    }

    const table_size = (argv.len + 2) * 4; // +2 for argc and the null terminator
    if (table_size > cursor) return error.StackOverflow;
    const table_start_unaligned = cursor - table_size;
    const table_start = std.mem.alignBackward(usize, table_start_unaligned, 16);

    std.mem.writeInt(u32, cpu.memory[table_start..][0..4], @intCast(argv.len), .little); // argc

    for (0..argv.len) |i| {
        const offset = 4 + (i * 4);
        std.mem.writeInt(u32, cpu.memory[table_start + offset ..][0..4], addresses[i], .little);
    }

    const null_offset = 4 + (argv.len * 4);
    std.mem.writeInt(u32, cpu.memory[table_start + null_offset ..][0..4], 0, .little);

    cpu.regs[2] = @intCast(table_start); // set sp to the new stack pointer
}
