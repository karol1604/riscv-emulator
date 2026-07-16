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

pub const Host = struct {
    // TODO: this should prolly contain like stdout and stderr and stuff

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
        _ = self;
        _ = cpu;
        switch (request.number) {
            64 => return error.WriteNotImplemented, // write
            93, 94 => return .{ .exited = request.args[0] }, // exit, exit_group
            else => {
                std.debug.print("Syscall number {d} not implemented\n", .{request.number});
                return error.SyscallNotImplemented;
            },
        }
    }
};
