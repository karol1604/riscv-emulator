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

    pub fn init(stdout: *std.Io.Writer, stderr: *std.Io.Writer) Host {
        return .{
            .stdout = stdout,
            .stderr = stderr,
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

    pub fn handleSyscall(self: *Host, cpu: *Cpu, request: SyscallRequest) !SyscallResult {
        switch (request.number) {
            64 => {
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
            93, 94 => return .{ .exited = request.args[0] }, // exit, exit_group
            else => {
                std.log.err("Syscall number {d} not implemented\n", .{request.number});
                return .{ .returned = errno(.ENOSYS) };
            },
        }
    }
};
