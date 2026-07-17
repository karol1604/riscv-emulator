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
    fault: cpu_mod.Fault,

    pub fn format(self: RunResult, writer: *std.Io.Writer) !void {
        switch (self) {
            .exited => |code| try writer.print("Program exited with code {d}", .{code}),
            .breakpoint => try writer.print("Breakpoint reached", .{}),
            .fault => |fault| {
                try writer.writeAll("Program faulted: ");
                try fault.format(writer);
            },
        }
    }
};

const Syscall = enum(u32) {
    OPENAT = 56,
    CLOSE = 57,
    READ = 63,
    WRITE = 64,
    EXIT = 93,
    EXIT_GROUP = 94,
    _,
};

const ErrorCode = enum(u32) {
    ENOENT = 2,
    EINTR = 4,
    EIO = 5,
    EBADF = 9,
    EAGAIN = 11,
    ENOMEM = 12,
    EACCES = 13,
    EFAULT = 14,
    EEXIST = 17,
    ENODEV = 19,
    ENOTDIR = 20,
    EISDIR = 21,
    EINVAL = 22,
    ENFILE = 23,
    EMFILE = 24,
    EFBIG = 27,
    ENOSPC = 28,
    ENAMETOOLONG = 36,
    ENOSYS = 38,
    ELOOP = 40,
    ECONNRESET = 104,
    ENOTCONN = 107,
};

fn errno(code: ErrorCode) u32 {
    return 0 -% @intFromEnum(code);
}

fn openErrorCode(err: anyerror) ErrorCode {
    return switch (err) {
        error.FileNotFound, error.NetworkNotFound => .ENOENT,
        error.AccessDenied, error.PermissionDenied, error.ReadOnlyFileSystem => .EACCES,
        error.SymLinkLoop => .ELOOP,
        error.ProcessFdQuotaExceeded => .EMFILE,
        error.SystemFdQuotaExceeded => .ENFILE,
        error.NoDevice => .ENODEV,
        error.NameTooLong => .ENAMETOOLONG,
        error.BadPathName => .EINVAL,
        error.IsDir => .EISDIR,
        error.NotDir => .ENOTDIR,
        error.PathAlreadyExists => .EEXIST,
        error.FileTooBig => .EFBIG,
        error.NoSpaceLeft => .ENOSPC,
        error.WouldBlock => .EAGAIN,
        error.SystemResources => .ENOMEM,
        error.Canceled => .EINTR,
        else => .EIO,
    };
}

fn readErrorCode(err: anyerror) ErrorCode {
    return switch (err) {
        error.InputOutput => .EIO,
        error.SystemResources => .ENOMEM,
        error.IsDir => .EISDIR,
        error.ConnectionResetByPeer => .ECONNRESET,
        error.NotOpenForReading => .EBADF,
        error.SocketUnconnected => .ENOTCONN,
        error.WouldBlock => .EAGAIN,
        error.AccessDenied, error.LockViolation => .EACCES,
        error.Canceled => .EINTR,
        else => .EIO,
    };
}

pub const Host = struct {
    stdout: *std.Io.Writer,
    stderr: *std.Io.Writer,
    stdin: *std.Io.Reader,
    io: std.Io,
    file_descriptors: [16]?std.Io.File,

    pub fn init(
        io: std.Io,
        stdout: *std.Io.Writer,
        stderr: *std.Io.Writer,
        stdin: *std.Io.Reader,
    ) Host {
        return .{
            .stdout = stdout,
            .stderr = stderr,
            .stdin = stdin,
            .io = io,
            .file_descriptors = [_]?std.Io.File{null} ** 16,
        };
    }

    pub fn deinit(self: *Host) void {
        for (&self.file_descriptors) |*descriptor| {
            if (descriptor.*) |file| {
                file.close(self.io);
                descriptor.* = null;
            }
        }
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
                .fault => |fault| return .{ .fault = fault },
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

    fn getFreeFileDescriptor(self: *Host) !usize {
        for (self.file_descriptors, 0..) |fd, idx| {
            if (fd == null) {
                return idx;
            }
        }
        return error.TooManyOpenFiles;
    }

    pub fn handleSyscall(self: *Host, cpu: *Cpu, request: SyscallRequest) !SyscallResult {
        const sc: Syscall = @enumFromInt(request.number);
        switch (sc) {
            .OPENAT => {
                const dirfd = request.args[0];
                const path_addr = request.args[1]; // address of null-terminated path
                const flags = request.args[2];
                const mode = request.args[3];

                if (dirfd != 0xffffff9c) {
                    return .{ .returned = errno(.EBADF) };
                }
                if (flags != 0 or mode != 0) {
                    return .{ .returned = errno(.EINVAL) };
                }

                const path = cpu.readNullTerminatedString(path_addr, 4096) catch |err| switch (err) {
                    error.OutOfBounds => return .{ .returned = errno(.EFAULT) },
                    error.NameTooLong => return .{ .returned = errno(.ENAMETOOLONG) },
                };

                const free_fd = self.getFreeFileDescriptor() catch {
                    return .{ .returned = errno(.EMFILE) };
                };

                const file = std.Io.Dir.cwd().openFile(self.io, path, .{}) catch |err| switch (err) {
                    else => return .{ .returned = errno(openErrorCode(err)) },
                };

                self.file_descriptors[free_fd] = file;
                return .{ .returned = @intCast(free_fd + 3) }; // return fd starting from 3
            },
            .CLOSE => {
                const fd = request.args[0];
                if (fd < 3) {
                    return .{ .returned = errno(.EBADF) };
                }

                const index = fd - 3;
                if (index >= self.file_descriptors.len) {
                    return .{ .returned = errno(.EBADF) };
                }
                const idx: usize = @intCast(index);

                const file = self.file_descriptors[idx] orelse {
                    return .{ .returned = errno(.EBADF) };
                };

                file.close(self.io);
                self.file_descriptors[idx] = null;
                return .{ .returned = 0 };
            },
            .READ => {
                const fd = request.args[0];
                const addr = request.args[1];
                const len = request.args[2];

                if (fd == 0) {
                    const cpu_buffer = cpu.getBytesMut(addr, len) catch {
                        return .{ .returned = errno(.EFAULT) };
                    };

                    const bytes_read = try readIntoGuest(self.stdin, cpu_buffer);

                    return .{ .returned = @intCast(bytes_read) };
                }

                if (fd < 3) {
                    return .{ .returned = errno(.EBADF) };
                }

                const index = fd - 3;
                if (index >= self.file_descriptors.len) {
                    return .{ .returned = errno(.EBADF) };
                }
                const idx: usize = @intCast(index);

                if (self.file_descriptors[idx] == null) {
                    return .{ .returned = errno(.EBADF) };
                }

                const guest_buf = cpu.getBytesMut(addr, len) catch {
                    return .{ .returned = errno(.EFAULT) };
                };
                const file = self.file_descriptors[idx].?;
                const bytes_read = file.readStreaming(self.io, &.{guest_buf}) catch |err|
                    switch (err) {
                        error.EndOfStream => 0,
                        else => return .{ .returned = errno(readErrorCode(err)) },
                    };

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
