const std = @import("std");
const builtin = @import("builtin");
const instruction = @import("instruction.zig");

const Register = instruction.Register;
const Instruction = instruction.Instruction;
const decode = instruction.decode;

pub const Cpu = struct {
    const memory_size = 64 * 1024;
    regs: [32]u32 = .{0} ** 32,
    /// Program counter
    pc: u32 = 0,
    memory: [memory_size]u8 = .{0} ** memory_size,

    /// Executes a number of instructions starting from the current program counter.
    pub fn run(self: *Cpu, instr_count: usize) !void {
        for (0..instr_count) |_| {
            try self.step();
        }
    }

    /// Executes instructions until a halt instruction is encountered
    /// or the maximum instruction count is reached.
    pub fn runUntilHalt(self: *Cpu, max_instr_count: usize) !void {
        for (0..max_instr_count) |_| {
            self.step() catch |err| switch (err) {
                error.Halted => return,
                else => return err,
            };
        }
        return error.InstructionLimitExceeded;
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

    fn step(self: *Cpu) !void {
        const instruction_pc = self.pc;
        const raw = try self.fetchInstruction();
        const instr = try decode(raw);

        if (!builtin.is_test) {
            std.debug.print("0x{x:0>8}: {f}\n", .{ self.pc, instr });
        }

        self.pc +%= 4; // increment before execution to handle branches correctly
        errdefer self.pc = instruction_pc;
        try self.executeInstruction(instr, instruction_pc);
    }

    fn executeInstruction(self: *Cpu, instr: Instruction, instruction_pc: u32) !void {
        switch (instr) {
            .addi => |i| {
                const imm: u32 = @bitCast(@as(i32, i.imm));
                self.writeRegister(i.rd, self.readRegister(i.rs1) +% imm);
            },
            .add => |i| {
                self.writeRegister(
                    i.rd,
                    self.readRegister(i.rs1) +% self.readRegister(i.rs2),
                );
            },
            .sub => |i| {
                self.writeRegister(
                    i.rd,
                    self.readRegister(i.rs1) -% self.readRegister(i.rs2),
                );
            },
            .andi => |i| {
                const imm: u32 = @bitCast(@as(i32, i.imm));
                self.writeRegister(i.rd, self.readRegister(i.rs1) & imm);
            },
            .@"and" => |i| {
                self.writeRegister(
                    i.rd,
                    self.readRegister(i.rs1) & self.readRegister(i.rs2),
                );
            },
            .ori => |i| {
                const imm: u32 = @bitCast(@as(i32, i.imm));
                self.writeRegister(i.rd, self.readRegister(i.rs1) | imm);
            },
            .@"or" => |i| {
                self.writeRegister(
                    i.rd,
                    self.readRegister(i.rs1) | self.readRegister(i.rs2),
                );
            },
            .xori => |i| {
                const imm: u32 = @bitCast(@as(i32, i.imm));
                self.writeRegister(i.rd, self.readRegister(i.rs1) ^ imm);
            },
            .xor => |i| {
                self.writeRegister(
                    i.rd,
                    self.readRegister(i.rs1) ^ self.readRegister(i.rs2),
                );
            },
            .sll => |i| {
                const shamt: u5 = @truncate(self.readRegister(i.rs2));
                self.writeRegister(i.rd, self.readRegister(i.rs1) << shamt);
            },
            .slli => |i| {
                self.writeRegister(i.rd, self.readRegister(i.rs1) << i.shamt);
            },
            .srl => |i| {
                const shamt: u5 = @truncate(self.readRegister(i.rs2));
                self.writeRegister(i.rd, self.readRegister(i.rs1) >> shamt);
            },
            .srli => |i| {
                self.writeRegister(i.rd, self.readRegister(i.rs1) >> i.shamt);
            },
            .sra => |i| {
                const shamt: u5 = @truncate(self.readRegister(i.rs2));
                const value: i32 = @bitCast(self.readRegister(i.rs1));
                const result: u32 = @bitCast(value >> shamt);
                self.writeRegister(i.rd, result);
            },
            .srai => |i| {
                const value: i32 = @bitCast(self.readRegister(i.rs1));
                const result: u32 = @bitCast(value >> i.shamt);
                self.writeRegister(i.rd, result);
            },
            .slt => |i| {
                const lhs: i32 = @bitCast(self.readRegister(i.rs1));
                const rhs: i32 = @bitCast(self.readRegister(i.rs2));
                self.writeRegister(i.rd, @intFromBool(lhs < rhs));
            },
            .sltu => |i| {
                const lhs = self.readRegister(i.rs1);
                const rhs = self.readRegister(i.rs2);
                self.writeRegister(i.rd, @intFromBool(lhs < rhs));
            },
            .slti => |i| {
                const lhs: i32 = @bitCast(self.readRegister(i.rs1));
                const rhs: i32 = @intCast(i.imm);
                self.writeRegister(i.rd, @intFromBool(lhs < rhs));
            },
            .sltiu => |i| {
                const lhs = self.readRegister(i.rs1);
                const rhs: u32 = @bitCast(@as(i32, i.imm));
                self.writeRegister(i.rd, @intFromBool(lhs < rhs));
            },
            .lw => |i| {
                const address = self.effectiveAddress(i.rs1, i.imm);
                const value = try self.readMemory(u32, address);
                self.writeRegister(i.rd, value);
            },
            .sw => |i| {
                const address = self.effectiveAddress(i.rs1, i.imm);
                try self.writeMemory(u32, address, self.readRegister(i.rs2));
            },
            .lb => |i| {
                const address = self.effectiveAddress(i.rs1, i.imm);
                const value: i8 = @bitCast(try self.readMemory(u8, address));
                const extended: i32 = @intCast(value);
                self.writeRegister(i.rd, @bitCast(extended));
            },
            .lbu => |i| {
                const address = self.effectiveAddress(i.rs1, i.imm);
                self.writeRegister(i.rd, @intCast(try self.readMemory(u8, address)));
            },
            .lh => |i| {
                const address = self.effectiveAddress(i.rs1, i.imm);
                const value: i16 = @bitCast(try self.readMemory(u16, address));
                const extended: i32 = @intCast(value);
                self.writeRegister(i.rd, @bitCast(extended));
            },
            .lhu => |i| {
                const address = self.effectiveAddress(i.rs1, i.imm);
                self.writeRegister(i.rd, @intCast(try self.readMemory(u16, address)));
            },
            .sb => |i| {
                const address = self.effectiveAddress(i.rs1, i.imm);
                const value: u8 = @truncate(self.readRegister(i.rs2));
                try self.writeMemory(u8, address, value);
            },
            .sh => |i| {
                const address = self.effectiveAddress(i.rs1, i.imm);
                const value: u16 = @truncate(self.readRegister(i.rs2));
                try self.writeMemory(u16, address, value);
            },
            .beq => |i| {
                if (self.readRegister(i.rs1) == self.readRegister(i.rs2)) {
                    try self.takeBranch(instruction_pc, i.imm);
                }
            },
            .bne => |i| {
                if (self.readRegister(i.rs1) != self.readRegister(i.rs2)) {
                    try self.takeBranch(instruction_pc, i.imm);
                }
            },
            .blt => |i| {
                const lhs: i32 = @bitCast(self.readRegister(i.rs1));
                const rhs: i32 = @bitCast(self.readRegister(i.rs2));
                if (lhs < rhs) {
                    try self.takeBranch(instruction_pc, i.imm);
                }
            },
            .bltu => |i| {
                const lhs = self.readRegister(i.rs1);
                const rhs = self.readRegister(i.rs2);
                if (lhs < rhs) {
                    try self.takeBranch(instruction_pc, i.imm);
                }
            },
            .bge => |i| {
                const lhs: i32 = @bitCast(self.readRegister(i.rs1));
                const rhs: i32 = @bitCast(self.readRegister(i.rs2));
                if (lhs >= rhs) {
                    try self.takeBranch(instruction_pc, i.imm);
                }
            },
            .bgeu => |i| {
                const lhs = self.readRegister(i.rs1);
                const rhs = self.readRegister(i.rs2);
                if (lhs >= rhs) {
                    try self.takeBranch(instruction_pc, i.imm);
                }
            },
            .jal => |i| {
                try self.takeBranch(instruction_pc, i.imm);
                self.writeRegister(i.rd, instruction_pc +% 4);
            },
            .jalr => |i| {
                const base = self.readRegister(i.rs1);
                const offset: u32 = @bitCast(@as(i32, i.imm));
                const target = (base +% offset) & ~@as(u32, 1);

                if (target % 4 != 0) return error.UnalignedAccess;

                self.writeRegister(i.rd, instruction_pc +% 4);
                self.pc = target;
            },
            .lui => |i| {
                self.writeRegister(i.rd, @as(u32, i.imm) << 12);
            },
            .auipc => |i| {
                self.writeRegister(i.rd, instruction_pc +% (@as(u32, i.imm) << 12));
            },
            .ebreak => {
                std.debug.print("EBREAK instruction executed at 0x{x:0>8}\n", .{instruction_pc});
                return error.Halted;
            },
        }
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
