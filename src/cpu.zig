const std = @import("std");
const builtin = @import("builtin");
const instruction = @import("instruction.zig");

const Register = instruction.Register;
const Instruction = instruction.Instruction;
const decode = instruction.decode;

pub const SyscallRequest = struct {
    number: u32,
    args: [6]u32,
};

pub const StepResult = union(enum) {
    running,
    syscall: SyscallRequest,
    breakpoint,
    fault: Fault,
};

pub const FaultReason = enum {
    instruction_address_misaligned,
    instruction_access_fault,
    illegal_instruction,
    load_address_misaligned,
    load_access_fault,
    store_address_misaligned,
    store_access_fault,
};

pub const Fault = struct {
    reason: FaultReason,
    pc: u32,
    value: u32,

    pub fn format(self: Fault, writer: *std.Io.Writer) !void {
        try writer.print(
            "{s} at PC=0x{x:0>8}, value=0x{x:0>8}",
            .{ @tagName(self.reason), self.pc, self.value },
        );
    }
};

pub const Cpu = struct {
    pub const memory_size = 128 * 1024;
    regs: [32]u32 = .{0} ** 32,
    /// Program counter
    pc: u32 = 0,
    memory: [memory_size]u8 = .{0} ** memory_size,

    /// Executes exactly `instr_count` ordinary instructions for instruction-level tests.
    pub fn runInstructionsForTesting(self: *Cpu, instr_count: usize) !void {
        if (!builtin.is_test) {
            @compileError("runInstructionsForTesting may only be used in tests");
        }

        for (0..instr_count) |_| {
            switch (try self.step()) {
                .running => {},
                .syscall, .breakpoint => return error.UnexpectedExecutionEvent,
                .fault => return error.UnexpectedCpuFault,
            }
        }
    }

    /// Returns a non-mutable slice of the CPU's memory starting at `address` and spanning `length` bytes.
    pub fn getBytes(self: *const Cpu, address: u32, length: usize) ![]const u8 {
        const start: usize = @intCast(address);
        if (start > self.memory.len or length > self.memory.len - start) {
            return error.OutOfBounds;
        }
        return self.memory[start..][0..length];
    }

    pub fn getBytesMut(self: *Cpu, address: u32, length: usize) ![]u8 {
        const start: usize = @intCast(address);
        if (start > self.memory.len or length > self.memory.len - start) {
            return error.OutOfBounds;
        }
        return self.memory[start..][0..length];
    }

    pub fn zeroOutMemory(self: *Cpu, start: usize, end: usize) void {
        if (start > end or end > self.memory.len) return;
        @memset(self.memory[start..end], 0);
    }

    pub fn dumpRegisters(self: *const Cpu) void {
        for (self.regs, 0..) |reg, i| {
            std.debug.print("x{d}: 0x{x:0>8} => 0b{b:0>32} => {d}\n", .{ i, reg, reg, reg });
        }
    }

    pub fn loadProgramAt(self: *Cpu, address: u32, program: []const u8) !void {
        const start: usize = @intCast(address);
        if (start > self.memory.len or program.len > self.memory.len - start) {
            return error.OutOfBounds;
        }
        @memcpy(self.memory[start..][0..program.len], program);
    }

    pub fn step(self: *Cpu) !StepResult {
        const instruction_pc = self.pc;
        const raw = self.fetchInstruction() catch |err| switch (err) {
            error.OutOfBounds => {
                return .{
                    .fault = .{
                        .reason = .instruction_access_fault,
                        .pc = instruction_pc,
                        .value = instruction_pc,
                    },
                };
            },
            error.UnalignedAccess => {
                return .{
                    .fault = .{
                        .reason = .instruction_address_misaligned,
                        .pc = instruction_pc,
                        .value = instruction_pc,
                    },
                };
            },
        };
        const instr = decode(raw) catch {
            return .{
                .fault = .{
                    .reason = .illegal_instruction,
                    .pc = instruction_pc,
                    .value = raw,
                },
            };
        };

        // if (!builtin.is_test) {
        //     std.debug.print("0x{x:0>8}: {f}\n", .{ self.pc, instr });
        // }

        self.pc +%= 4; // increment before execution to handle branches correctly
        errdefer self.pc = instruction_pc;
        if (self.executeInstruction(instr, instruction_pc)) |fault| {
            self.pc = instruction_pc; // restore PC on fault
            return .{ .fault = fault };
        }

        if (instr == .ebreak) return .{ .breakpoint = {} };
        if (instr == .ecall) {
            const syscall_request = SyscallRequest{
                .number = self.readRegister(.x17),
                .args = .{
                    self.readRegister(.x10),
                    self.readRegister(.x11),
                    self.readRegister(.x12),
                    self.readRegister(.x13),
                    self.readRegister(.x14),
                    self.readRegister(.x15),
                },
            };
            return .{ .syscall = syscall_request };
        }
        return .{ .running = {} };
    }

    fn executeInstruction(self: *Cpu, instr: Instruction, instruction_pc: u32) ?Fault {
        switch (instr) {
            .addi => |i| {
                const imm: u32 = @bitCast(@as(i32, i.imm));
                self.writeRegister(i.rd, self.readRegister(i.rs1) +% imm);
                return null;
            },
            .add => |i| {
                self.writeRegister(
                    i.rd,
                    self.readRegister(i.rs1) +% self.readRegister(i.rs2),
                );
                return null;
            },
            .sub => |i| {
                self.writeRegister(
                    i.rd,
                    self.readRegister(i.rs1) -% self.readRegister(i.rs2),
                );
                return null;
            },
            .andi => |i| {
                const imm: u32 = @bitCast(@as(i32, i.imm));
                self.writeRegister(i.rd, self.readRegister(i.rs1) & imm);
                return null;
            },
            .@"and" => |i| {
                self.writeRegister(
                    i.rd,
                    self.readRegister(i.rs1) & self.readRegister(i.rs2),
                );
                return null;
            },
            .ori => |i| {
                const imm: u32 = @bitCast(@as(i32, i.imm));
                self.writeRegister(i.rd, self.readRegister(i.rs1) | imm);
                return null;
            },
            .@"or" => |i| {
                self.writeRegister(
                    i.rd,
                    self.readRegister(i.rs1) | self.readRegister(i.rs2),
                );
                return null;
            },
            .xori => |i| {
                const imm: u32 = @bitCast(@as(i32, i.imm));
                self.writeRegister(i.rd, self.readRegister(i.rs1) ^ imm);
                return null;
            },
            .xor => |i| {
                self.writeRegister(
                    i.rd,
                    self.readRegister(i.rs1) ^ self.readRegister(i.rs2),
                );
                return null;
            },
            .sll => |i| {
                const shamt: u5 = @truncate(self.readRegister(i.rs2));
                self.writeRegister(i.rd, self.readRegister(i.rs1) << shamt);
                return null;
            },
            .slli => |i| {
                self.writeRegister(i.rd, self.readRegister(i.rs1) << i.shamt);
                return null;
            },
            .srl => |i| {
                const shamt: u5 = @truncate(self.readRegister(i.rs2));
                self.writeRegister(i.rd, self.readRegister(i.rs1) >> shamt);
                return null;
            },
            .srli => |i| {
                self.writeRegister(i.rd, self.readRegister(i.rs1) >> i.shamt);
                return null;
            },
            .sra => |i| {
                const shamt: u5 = @truncate(self.readRegister(i.rs2));
                const value: i32 = @bitCast(self.readRegister(i.rs1));
                const result: u32 = @bitCast(value >> shamt);
                self.writeRegister(i.rd, result);
                return null;
            },
            .srai => |i| {
                const value: i32 = @bitCast(self.readRegister(i.rs1));
                const result: u32 = @bitCast(value >> i.shamt);
                self.writeRegister(i.rd, result);
                return null;
            },
            .slt => |i| {
                const lhs: i32 = @bitCast(self.readRegister(i.rs1));
                const rhs: i32 = @bitCast(self.readRegister(i.rs2));
                self.writeRegister(i.rd, @intFromBool(lhs < rhs));
                return null;
            },
            .sltu => |i| {
                const lhs = self.readRegister(i.rs1);
                const rhs = self.readRegister(i.rs2);
                self.writeRegister(i.rd, @intFromBool(lhs < rhs));
                return null;
            },
            .slti => |i| {
                const lhs: i32 = @bitCast(self.readRegister(i.rs1));
                const rhs: i32 = @intCast(i.imm);
                self.writeRegister(i.rd, @intFromBool(lhs < rhs));
                return null;
            },
            .sltiu => |i| {
                const lhs = self.readRegister(i.rs1);
                const rhs: u32 = @bitCast(@as(i32, i.imm));
                self.writeRegister(i.rd, @intFromBool(lhs < rhs));
                return null;
            },
            .lw => |i| {
                const address = self.effectiveAddress(i.rs1, i.imm);
                const value = self.readMemory(u32, address) catch |err| switch (err) {
                    error.OutOfBounds => return .{
                        .reason = .load_access_fault,
                        .pc = instruction_pc,
                        .value = address,
                    },
                    error.UnalignedAccess => return .{
                        .reason = .load_address_misaligned,
                        .pc = instruction_pc,
                        .value = address,
                    },
                };
                self.writeRegister(i.rd, value);
                return null;
            },
            .sw => |i| {
                const address = self.effectiveAddress(i.rs1, i.imm);
                return self.isFaultWriteMemory(
                    u32,
                    address,
                    self.readRegister(i.rs2),
                    instruction_pc,
                );
            },
            .lb => |i| {
                const address = self.effectiveAddress(i.rs1, i.imm);
                const mem = self.readMemory(u8, address) catch |err| switch (err) {
                    error.OutOfBounds => return .{
                        .reason = .load_access_fault,
                        .pc = instruction_pc,
                        .value = address,
                    },
                    error.UnalignedAccess => return .{
                        .reason = .load_address_misaligned,
                        .pc = instruction_pc,
                        .value = address,
                    },
                };
                const value: i8 = @bitCast(mem);
                const extended: i32 = @intCast(value);
                self.writeRegister(i.rd, @bitCast(extended));
                return null;
            },
            .lbu => |i| {
                const address = self.effectiveAddress(i.rs1, i.imm);
                const mem = self.readMemory(u8, address) catch |err| switch (err) {
                    error.OutOfBounds => return .{
                        .reason = .load_access_fault,
                        .pc = instruction_pc,
                        .value = address,
                    },
                    error.UnalignedAccess => return .{
                        .reason = .load_address_misaligned,
                        .pc = instruction_pc,
                        .value = address,
                    },
                };
                self.writeRegister(i.rd, @intCast(mem));
                return null;
            },
            .lh => |i| {
                const address = self.effectiveAddress(i.rs1, i.imm);
                const mem = self.readMemory(u16, address) catch |err| switch (err) {
                    error.OutOfBounds => return .{
                        .reason = .load_access_fault,
                        .pc = instruction_pc,
                        .value = address,
                    },
                    error.UnalignedAccess => return .{
                        .reason = .load_address_misaligned,
                        .pc = instruction_pc,
                        .value = address,
                    },
                };
                const value: i16 = @bitCast(mem);
                const extended: i32 = @intCast(value);
                self.writeRegister(i.rd, @bitCast(extended));
                return null;
            },
            .lhu => |i| {
                const address = self.effectiveAddress(i.rs1, i.imm);
                const mem = self.readMemory(u16, address) catch |err| switch (err) {
                    error.OutOfBounds => return .{
                        .reason = .load_access_fault,
                        .pc = instruction_pc,
                        .value = address,
                    },
                    error.UnalignedAccess => return .{
                        .reason = .load_address_misaligned,
                        .pc = instruction_pc,
                        .value = address,
                    },
                };
                self.writeRegister(i.rd, @intCast(mem));
                return null;
            },
            .sb => |i| {
                const address = self.effectiveAddress(i.rs1, i.imm);
                const value: u8 = @truncate(self.readRegister(i.rs2));
                return self.isFaultWriteMemory(u8, address, value, instruction_pc);
            },
            .sh => |i| {
                const address = self.effectiveAddress(i.rs1, i.imm);
                const value: u16 = @truncate(self.readRegister(i.rs2));
                return self.isFaultWriteMemory(u16, address, value, instruction_pc);
            },
            .beq => |i| {
                if (self.readRegister(i.rs1) == self.readRegister(i.rs2)) {
                    return self.isFaultTakeBranch(instruction_pc, i.imm);
                }
                return null;
            },
            .bne => |i| {
                if (self.readRegister(i.rs1) != self.readRegister(i.rs2)) {
                    return self.isFaultTakeBranch(instruction_pc, i.imm);
                }
                return null;
            },
            .blt => |i| {
                const lhs: i32 = @bitCast(self.readRegister(i.rs1));
                const rhs: i32 = @bitCast(self.readRegister(i.rs2));
                if (lhs < rhs) {
                    return self.isFaultTakeBranch(instruction_pc, i.imm);
                }
                return null;
            },
            .bltu => |i| {
                const lhs = self.readRegister(i.rs1);
                const rhs = self.readRegister(i.rs2);
                if (lhs < rhs) {
                    return self.isFaultTakeBranch(instruction_pc, i.imm);
                }
                return null;
            },
            .bge => |i| {
                const lhs: i32 = @bitCast(self.readRegister(i.rs1));
                const rhs: i32 = @bitCast(self.readRegister(i.rs2));
                if (lhs >= rhs) {
                    return self.isFaultTakeBranch(instruction_pc, i.imm);
                }
                return null;
            },
            .bgeu => |i| {
                const lhs = self.readRegister(i.rs1);
                const rhs = self.readRegister(i.rs2);
                if (lhs >= rhs) {
                    return self.isFaultTakeBranch(instruction_pc, i.imm);
                }
                return null;
            },
            .jal => |i| {
                if (self.isFaultTakeBranch(instruction_pc, i.imm)) |fault| return fault;
                self.writeRegister(i.rd, instruction_pc +% 4);
                return null;
            },
            .jalr => |i| {
                const base = self.readRegister(i.rs1);
                const offset: u32 = @bitCast(@as(i32, i.imm));
                const target = (base +% offset) & ~@as(u32, 1);

                if (target % 4 != 0) return .{
                    .reason = .instruction_address_misaligned,
                    .pc = instruction_pc,
                    .value = target,
                };

                self.writeRegister(i.rd, instruction_pc +% 4);
                self.pc = target;
                return null;
            },
            .lui => |i| {
                self.writeRegister(i.rd, @as(u32, i.imm) << 12);
                return null;
            },
            .auipc => |i| {
                self.writeRegister(i.rd, instruction_pc +% (@as(u32, i.imm) << 12));
                return null;
            },
            .ebreak => {
                if (!builtin.is_test) {
                    std.debug.print("EBREAK instruction executed at 0x{x:0>8}\n", .{instruction_pc});
                }
                return null;
            },
            .mul => |i| {
                const lhs = self.readRegister(i.rs1);
                const rhs = self.readRegister(i.rs2);
                const prod: u64 = @as(u64, lhs) * @as(u64, rhs);
                const result: u32 = @truncate(prod);
                self.writeRegister(i.rd, result);
                return null;
            },
            .mulhu => |i| {
                const lhs = self.readRegister(i.rs1);
                const rhs = self.readRegister(i.rs2);
                const prod: u64 = @as(u64, lhs) * @as(u64, rhs);
                const result: u32 = @truncate(prod >> 32);
                self.writeRegister(i.rd, result);
                return null;
            },
            .mulh => |i| {
                const lhs: i32 = @bitCast(self.readRegister(i.rs1));
                const rhs: i32 = @bitCast(self.readRegister(i.rs2));
                const prod: i64 = @as(i64, lhs) * @as(i64, rhs);
                const prod_bits: u64 = @bitCast(prod);
                self.writeRegister(i.rd, @truncate(prod_bits >> 32));
                return null;
            },
            .mulhsu => |i| {
                const lhs: i32 = @bitCast(self.readRegister(i.rs1));
                const rhs = self.readRegister(i.rs2);
                const prod: i64 = @as(i64, lhs) * @as(i64, rhs);
                const prod_bits: u64 = @bitCast(prod);
                self.writeRegister(i.rd, @truncate(prod_bits >> 32));
                return null;
            },
            .div => |i| {
                const dividend: i32 = @bitCast(self.readRegister(i.rs1));
                const divisor: i32 = @bitCast(self.readRegister(i.rs2));
                if (divisor == 0) {
                    self.writeRegister(i.rd, 0xffff_ffff);
                } else if (dividend == std.math.minInt(i32) and divisor == -1) {
                    self.writeRegister(i.rd, @bitCast(dividend));
                } else {
                    const result = @divTrunc(dividend, divisor);
                    self.writeRegister(i.rd, @bitCast(result));
                }
                return null;
            },
            .rem => |i| {
                const dividend: i32 = @bitCast(self.readRegister(i.rs1));
                const divisor: i32 = @bitCast(self.readRegister(i.rs2));
                if (divisor == 0) {
                    self.writeRegister(i.rd, @bitCast(dividend));
                } else if (dividend == std.math.minInt(i32) and divisor == -1) {
                    self.writeRegister(i.rd, 0);
                } else {
                    const result: i32 = @rem(dividend, divisor);
                    self.writeRegister(i.rd, @bitCast(result));
                }
                return null;
            },
            .divu => |i| {
                const dividend = self.readRegister(i.rs1);
                const divisor = self.readRegister(i.rs2);
                if (divisor == 0) {
                    self.writeRegister(i.rd, 0xffff_ffff);
                } else {
                    const result = @divTrunc(dividend, divisor);
                    self.writeRegister(i.rd, result);
                }
                return null;
            },
            .remu => |i| {
                const dividend = self.readRegister(i.rs1);
                const divisor = self.readRegister(i.rs2);
                if (divisor == 0) {
                    self.writeRegister(i.rd, dividend);
                } else {
                    const result = @rem(dividend, divisor);
                    self.writeRegister(i.rd, result);
                }
                return null;
            },
            .ecall => {
                return null;
            },
            // else => return error.UnsupportedInstruction,
        }
    }

    fn isFaultTakeBranch(self: *Cpu, instruction_pc: u32, offset: anytype) ?Fault {
        self.takeBranch(instruction_pc, offset) catch |err| switch (err) {
            error.UnalignedAccess => {
                const ib: u32 = @bitCast(@as(i32, offset));
                return .{
                    .reason = .instruction_address_misaligned,
                    .pc = instruction_pc,
                    .value = instruction_pc +% ib,
                };
            },
        };
        return null;
    }

    fn takeBranch(self: *Cpu, instruction_pc: u32, offset: anytype) !void {
        const offset_bits: u32 = @bitCast(@as(i32, offset));
        const target = instruction_pc +% offset_bits;
        if (target % 4 != 0) return error.UnalignedAccess;
        self.pc = target;
    }

    fn effectiveAddress(self: *const Cpu, base: Register, offset: i12) u32 {
        const base_value = self.readRegister(base);
        const offset_value: u32 = @bitCast(@as(i32, offset));
        return base_value +% offset_value;
    }

    fn validateAccess(self: *const Cpu, address: u32, comptime T: type) !usize {
        const addr: usize = @intCast(address);
        const size = @sizeOf(T);

        if (addr + size > self.memory.len) return error.OutOfBounds;
        if (addr % size != 0) return error.UnalignedAccess;
        return addr;
    }

    fn readMemory(self: *const Cpu, comptime T: type, address: u32) !T {
        const addr = try self.validateAccess(address, T);
        if (T == u8) return self.memory[addr];
        return std.mem.readInt(T, self.memory[addr..][0..@sizeOf(T)], .little);
    }

    fn isFaultWriteMemory(
        self: *Cpu,
        comptime T: type,
        address: u32,
        value: T,
        instruction_pc: u32,
    ) ?Fault {
        self.writeMemory(T, address, value) catch |err| switch (err) {
            error.OutOfBounds => {
                return .{
                    .reason = .store_access_fault,
                    .pc = instruction_pc,
                    .value = address,
                };
            },
            error.UnalignedAccess => {
                return .{
                    .reason = .store_address_misaligned,
                    .pc = instruction_pc,
                    .value = address,
                };
            },
        };
        return null;
    }

    fn writeMemory(self: *Cpu, comptime T: type, address: u32, value: T) !void {
        const addr = try self.validateAccess(address, T);
        if (T == u8) {
            self.memory[addr] = value;
            return;
        }
        std.mem.writeInt(T, self.memory[addr..][0..@sizeOf(T)], value, .little);
    }

    fn fetchInstruction(self: *const Cpu) !u32 {
        const pc: usize = @intCast(self.pc);

        if (pc + 4 > self.memory.len) return error.OutOfBounds;
        if (pc % 4 != 0) return error.UnalignedAccess;

        return std.mem.readInt(u32, self.memory[pc..][0..4], .little);
    }

    fn readRegister(self: *const Cpu, reg: Register) u32 {
        return self.regs[@intFromEnum(reg)];
    }

    fn writeRegister(self: *Cpu, reg: Register, value: u32) void {
        if (reg == .x0) return;
        self.regs[@intFromEnum(reg)] = value;
    }
};
