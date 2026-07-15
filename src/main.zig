const std = @import("std");
const builtin = @import("builtin");

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

        // Set the default next instruction before execution so a future control-flow
        // instruction can override it.
        self.pc +%= 4;
        errdefer self.pc = instruction_pc;
        try self.executeInstruction(instr);
    }

    fn executeInstruction(self: *Cpu, instr: Instruction) !void {
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
        }
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

// zig fmt: off
const Register = enum(u5) {
    x0 = 0, x1, x2, x3, x4, x5, x6, x7,
    x8, x9, x10, x11, x12, x13, x14, x15, x16, x17,
    x18, x19, x20, x21, x22, x23, x24, x25, x26, x27, x28, x29, x30, x31,
};
// zig fmt: on

const Instruction = union(enum) {
    addi: struct {
        rd: Register,
        rs1: Register,
        imm: i12,
    },
    add: struct {
        rd: Register,
        rs1: Register,
        rs2: Register,
    },
    sub: struct {
        rd: Register,
        rs1: Register,
        rs2: Register,
    },
    andi: struct {
        rd: Register,
        rs1: Register,
        imm: i12,
    },
    @"and": struct {
        rd: Register,
        rs1: Register,
        rs2: Register,
    },
    ori: struct {
        rd: Register,
        rs1: Register,
        imm: i12,
    },
    @"or": struct {
        rd: Register,
        rs1: Register,
        rs2: Register,
    },
    xori: struct {
        rd: Register,
        rs1: Register,
        imm: i12,
    },
    xor: struct {
        rd: Register,
        rs1: Register,
        rs2: Register,
    },
    sll: struct {
        rd: Register,
        rs1: Register,
        rs2: Register,
    },
    slli: struct {
        rd: Register,
        rs1: Register,
        shamt: u5,
    },
    srl: struct {
        rd: Register,
        rs1: Register,
        rs2: Register,
    },
    srli: struct {
        rd: Register,
        rs1: Register,
        shamt: u5,
    },
    sra: struct {
        rd: Register,
        rs1: Register,
        rs2: Register,
    },
    srai: struct {
        rd: Register,
        rs1: Register,
        shamt: u5,
    },
    slt: struct {
        rd: Register,
        rs1: Register,
        rs2: Register,
    },
    sltu: struct {
        rd: Register,
        rs1: Register,
        rs2: Register,
    },
    slti: struct {
        rd: Register,
        rs1: Register,
        imm: i12,
    },
    sltiu: struct {
        rd: Register,
        rs1: Register,
        imm: i12,
    },
    lw: struct {
        rd: Register,
        rs1: Register,
        imm: i12,
    },
    sw: struct {
        rs1: Register,
        rs2: Register,
        imm: i12,
    },
    lb: struct {
        rd: Register,
        rs1: Register,
        imm: i12,
    },
    lbu: struct {
        rd: Register,
        rs1: Register,
        imm: i12,
    },
    lh: struct {
        rd: Register,
        rs1: Register,
        imm: i12,
    },
    lhu: struct {
        rd: Register,
        rs1: Register,
        imm: i12,
    },
    sb: struct {
        rs1: Register,
        rs2: Register,
        imm: i12,
    },
    sh: struct {
        rs1: Register,
        rs2: Register,
        imm: i12,
    },

    pub fn format(self: Instruction, writer: *std.Io.Writer) !void {
        switch (self) {
            .addi => |instr| {
                try writer.print("addi {s}, {s}, {d}", .{
                    @tagName(instr.rd),
                    @tagName(instr.rs1),
                    instr.imm,
                });
            },
            .add => |instr| {
                try writer.print("add {s}, {s}, {s}", .{
                    @tagName(instr.rd),
                    @tagName(instr.rs1),
                    @tagName(instr.rs2),
                });
            },
            .sub => |instr| {
                try writer.print("sub {s}, {s}, {s}", .{
                    @tagName(instr.rd),
                    @tagName(instr.rs1),
                    @tagName(instr.rs2),
                });
            },
            .andi => |instr| {
                try writer.print("andi {s}, {s}, {d}", .{
                    @tagName(instr.rd),
                    @tagName(instr.rs1),
                    instr.imm,
                });
            },
            .@"and" => |instr| {
                try writer.print("and {s}, {s}, {s}", .{
                    @tagName(instr.rd),
                    @tagName(instr.rs1),
                    @tagName(instr.rs2),
                });
            },
            .ori => |instr| {
                try writer.print("ori {s}, {s}, {d}", .{
                    @tagName(instr.rd),
                    @tagName(instr.rs1),
                    instr.imm,
                });
            },
            .@"or" => |instr| {
                try writer.print("or {s}, {s}, {s}", .{
                    @tagName(instr.rd),
                    @tagName(instr.rs1),
                    @tagName(instr.rs2),
                });
            },
            .xori => |instr| {
                try writer.print("xori {s}, {s}, {d}", .{
                    @tagName(instr.rd),
                    @tagName(instr.rs1),
                    instr.imm,
                });
            },
            .xor => |instr| {
                try writer.print("xor {s}, {s}, {s}", .{
                    @tagName(instr.rd),
                    @tagName(instr.rs1),
                    @tagName(instr.rs2),
                });
            },
            .sll => |instr| {
                try writer.print("sll {s}, {s}, {s}", .{
                    @tagName(instr.rd),
                    @tagName(instr.rs1),
                    @tagName(instr.rs2),
                });
            },
            .slli => |instr| {
                try writer.print("slli {s}, {s}, {d}", .{
                    @tagName(instr.rd),
                    @tagName(instr.rs1),
                    instr.shamt,
                });
            },
            .srl => |instr| {
                try writer.print("srl {s}, {s}, {s}", .{
                    @tagName(instr.rd),
                    @tagName(instr.rs1),
                    @tagName(instr.rs2),
                });
            },
            .srli => |instr| {
                try writer.print("srli {s}, {s}, {d}", .{
                    @tagName(instr.rd),
                    @tagName(instr.rs1),
                    instr.shamt,
                });
            },
            .sra => |instr| {
                try writer.print("sra {s}, {s}, {s}", .{
                    @tagName(instr.rd),
                    @tagName(instr.rs1),
                    @tagName(instr.rs2),
                });
            },
            .srai => |instr| {
                try writer.print("srai {s}, {s}, {d}", .{
                    @tagName(instr.rd),
                    @tagName(instr.rs1),
                    instr.shamt,
                });
            },
            .slt => |instr| {
                try writer.print("slt {s}, {s}, {s}", .{
                    @tagName(instr.rd),
                    @tagName(instr.rs1),
                    @tagName(instr.rs2),
                });
            },
            .sltu => |instr| {
                try writer.print("sltu {s}, {s}, {s}", .{
                    @tagName(instr.rd),
                    @tagName(instr.rs1),
                    @tagName(instr.rs2),
                });
            },
            .slti => |instr| {
                try writer.print("slti {s}, {s}, {d}", .{
                    @tagName(instr.rd),
                    @tagName(instr.rs1),
                    instr.imm,
                });
            },
            .sltiu => |instr| {
                try writer.print("sltiu {s}, {s}, {d}", .{
                    @tagName(instr.rd),
                    @tagName(instr.rs1),
                    instr.imm,
                });
            },
            .lw => |instr| {
                try writer.print("lw {s}, {d}({s})", .{
                    @tagName(instr.rd),
                    instr.imm,
                    @tagName(instr.rs1),
                });
            },
            .sw => |instr| {
                try writer.print("sw {s}, {d}({s})", .{
                    @tagName(instr.rs2),
                    instr.imm,
                    @tagName(instr.rs1),
                });
            },
            .lb => |instr| {
                try writer.print("lb {s}, {d}({s})", .{
                    @tagName(instr.rd),
                    instr.imm,
                    @tagName(instr.rs1),
                });
            },
            .lbu => |instr| {
                try writer.print("lbu {s}, {d}({s})", .{
                    @tagName(instr.rd),
                    instr.imm,
                    @tagName(instr.rs1),
                });
            },
            .lh => |instr| {
                try writer.print("lh {s}, {d}({s})", .{
                    @tagName(instr.rd),
                    instr.imm,
                    @tagName(instr.rs1),
                });
            },
            .lhu => |instr| {
                try writer.print("lhu {s}, {d}({s})", .{
                    @tagName(instr.rd),
                    instr.imm,
                    @tagName(instr.rs1),
                });
            },
            .sb => |instr| {
                try writer.print("sb {s}, {d}({s})", .{
                    @tagName(instr.rs2),
                    instr.imm,
                    @tagName(instr.rs1),
                });
            },
            .sh => |instr| {
                try writer.print("sh {s}, {d}({s})", .{
                    @tagName(instr.rs2),
                    instr.imm,
                    @tagName(instr.rs1),
                });
            },
        }
    }
};

const RawInstructionTypeI = packed struct(u32) {
    opcode: u7,
    rd: u5,
    funct3: u3,
    rs1: u5,
    imm: i12,
};

const RawInstructionTypeS = packed struct(u32) {
    opcode: u7,
    imm4_0: u5,
    funct3: u3,
    rs1: u5,
    rs2: u5,
    imm11_5: u7,
};

fn decodeStoreImmediate(raw: RawInstructionTypeS) i12 {
    const bits: u12 = (@as(u12, raw.imm11_5) << 5) | raw.imm4_0;
    return @bitCast(bits);
}

const RawInstructionTypeShiftI = packed struct(u32) {
    opcode: u7,
    rd: u5,
    funct3: u3,
    rs1: u5,
    shamt: u5,
    funct7: u7,
};

const RawInstructionTypeR = packed struct(u32) {
    opcode: u7,
    rd: u5,
    funct3: u3,
    rs1: u5,
    rs2: u5,
    funct7: u7,
};

const OpCode = enum(u7) {
    op_imm = 0b0010011,
    op_reg = 0b0110011,
    load = 0b0000011,
    store = 0b0100011,
    _,
};

fn opcode(instruction: u32) OpCode {
    const op: u7 = @intCast(instruction & 0b1111111);
    return @enumFromInt(op);
}

fn decode(instruction: u32) !Instruction {
    const op = opcode(instruction);

    switch (op) {
        .op_imm => {
            const raw: RawInstructionTypeI = @bitCast(instruction);
            switch (raw.funct3) {
                0b000 => {
                    return .{ .addi = .{
                        .rd = @enumFromInt(raw.rd),
                        .rs1 = @enumFromInt(raw.rs1),
                        .imm = raw.imm,
                    } };
                },
                0b111 => {
                    return .{ .andi = .{
                        .rd = @enumFromInt(raw.rd),
                        .rs1 = @enumFromInt(raw.rs1),
                        .imm = raw.imm,
                    } };
                },
                0b110 => {
                    return .{ .ori = .{
                        .rd = @enumFromInt(raw.rd),
                        .rs1 = @enumFromInt(raw.rs1),
                        .imm = raw.imm,
                    } };
                },
                0b100 => {
                    return .{ .xori = .{
                        .rd = @enumFromInt(raw.rd),
                        .rs1 = @enumFromInt(raw.rs1),
                        .imm = raw.imm,
                    } };
                },
                0b001 => {
                    const shift: RawInstructionTypeShiftI = @bitCast(instruction);
                    if (shift.funct7 != 0b0000000) return error.UnsupportedInstruction;

                    return .{ .slli = .{
                        .rd = @enumFromInt(shift.rd),
                        .rs1 = @enumFromInt(shift.rs1),
                        .shamt = shift.shamt,
                    } };
                },
                0b101 => {
                    const shift: RawInstructionTypeShiftI = @bitCast(instruction);
                    switch (shift.funct7) {
                        0b0000000 => {
                            return .{ .srli = .{
                                .rd = @enumFromInt(shift.rd),
                                .rs1 = @enumFromInt(shift.rs1),
                                .shamt = shift.shamt,
                            } };
                        },
                        0b0100000 => {
                            return .{ .srai = .{
                                .rd = @enumFromInt(shift.rd),
                                .rs1 = @enumFromInt(shift.rs1),
                                .shamt = shift.shamt,
                            } };
                        },
                        else => return error.UnsupportedInstruction,
                    }
                },
                0b010 => {
                    return .{ .slti = .{
                        .rd = @enumFromInt(raw.rd),
                        .rs1 = @enumFromInt(raw.rs1),
                        .imm = raw.imm,
                    } };
                },
                0b011 => {
                    return .{ .sltiu = .{
                        .rd = @enumFromInt(raw.rd),
                        .rs1 = @enumFromInt(raw.rs1),
                        .imm = raw.imm,
                    } };
                },
            }
        },
        .op_reg => {
            const raw: RawInstructionTypeR = @bitCast(instruction);
            switch (raw.funct3) {
                0b000 => {
                    switch (raw.funct7) {
                        0b0000000 => {
                            return .{ .add = .{
                                .rd = @enumFromInt(raw.rd),
                                .rs1 = @enumFromInt(raw.rs1),
                                .rs2 = @enumFromInt(raw.rs2),
                            } };
                        },
                        0b0100000 => {
                            return .{ .sub = .{
                                .rd = @enumFromInt(raw.rd),
                                .rs1 = @enumFromInt(raw.rs1),
                                .rs2 = @enumFromInt(raw.rs2),
                            } };
                        },
                        else => return error.UnsupportedInstruction,
                    }
                },
                0b111 => {
                    switch (raw.funct7) {
                        0b0000000 => {
                            return .{ .@"and" = .{
                                .rd = @enumFromInt(raw.rd),
                                .rs1 = @enumFromInt(raw.rs1),
                                .rs2 = @enumFromInt(raw.rs2),
                            } };
                        },
                        else => return error.UnsupportedInstruction,
                    }
                },
                0b110 => {
                    switch (raw.funct7) {
                        0b0000000 => {
                            return .{ .@"or" = .{
                                .rd = @enumFromInt(raw.rd),
                                .rs1 = @enumFromInt(raw.rs1),
                                .rs2 = @enumFromInt(raw.rs2),
                            } };
                        },
                        else => return error.UnsupportedInstruction,
                    }
                },
                0b100 => {
                    switch (raw.funct7) {
                        0b0000000 => {
                            return .{ .xor = .{
                                .rd = @enumFromInt(raw.rd),
                                .rs1 = @enumFromInt(raw.rs1),
                                .rs2 = @enumFromInt(raw.rs2),
                            } };
                        },
                        else => return error.UnsupportedInstruction,
                    }
                },
                0b001 => {
                    switch (raw.funct7) {
                        0b0000000 => {
                            return .{ .sll = .{
                                .rd = @enumFromInt(raw.rd),
                                .rs1 = @enumFromInt(raw.rs1),
                                .rs2 = @enumFromInt(raw.rs2),
                            } };
                        },
                        else => return error.UnsupportedInstruction,
                    }
                },
                0b101 => {
                    switch (raw.funct7) {
                        0b0000000 => {
                            return .{ .srl = .{
                                .rd = @enumFromInt(raw.rd),
                                .rs1 = @enumFromInt(raw.rs1),
                                .rs2 = @enumFromInt(raw.rs2),
                            } };
                        },
                        0b0100000 => {
                            return .{ .sra = .{
                                .rd = @enumFromInt(raw.rd),
                                .rs1 = @enumFromInt(raw.rs1),
                                .rs2 = @enumFromInt(raw.rs2),
                            } };
                        },
                        else => return error.UnsupportedInstruction,
                    }
                },
                0b010 => {
                    switch (raw.funct7) {
                        0b0000000 => {
                            return .{ .slt = .{
                                .rd = @enumFromInt(raw.rd),
                                .rs1 = @enumFromInt(raw.rs1),
                                .rs2 = @enumFromInt(raw.rs2),
                            } };
                        },
                        else => return error.UnsupportedInstruction,
                    }
                },
                0b011 => {
                    switch (raw.funct7) {
                        0b0000000 => {
                            return .{ .sltu = .{
                                .rd = @enumFromInt(raw.rd),
                                .rs1 = @enumFromInt(raw.rs1),
                                .rs2 = @enumFromInt(raw.rs2),
                            } };
                        },
                        else => return error.UnsupportedInstruction,
                    }
                },
            }
        },
        .load => {
            const raw: RawInstructionTypeI = @bitCast(instruction);
            switch (raw.funct3) {
                0b010 => {
                    return .{ .lw = .{
                        .rd = @enumFromInt(raw.rd),
                        .rs1 = @enumFromInt(raw.rs1),
                        .imm = raw.imm,
                    } };
                },
                0b000 => {
                    return .{ .lb = .{
                        .rd = @enumFromInt(raw.rd),
                        .rs1 = @enumFromInt(raw.rs1),
                        .imm = raw.imm,
                    } };
                },
                0b100 => {
                    return .{ .lbu = .{
                        .rd = @enumFromInt(raw.rd),
                        .rs1 = @enumFromInt(raw.rs1),
                        .imm = raw.imm,
                    } };
                },
                0b001 => {
                    return .{ .lh = .{
                        .rd = @enumFromInt(raw.rd),
                        .rs1 = @enumFromInt(raw.rs1),
                        .imm = raw.imm,
                    } };
                },
                0b101 => {
                    return .{ .lhu = .{
                        .rd = @enumFromInt(raw.rd),
                        .rs1 = @enumFromInt(raw.rs1),
                        .imm = raw.imm,
                    } };
                },
                else => return error.UnsupportedInstruction,
            }
        },
        .store => {
            const raw: RawInstructionTypeS = @bitCast(instruction);
            const imm = decodeStoreImmediate(raw);
            switch (raw.funct3) {
                0b010 => {
                    return .{ .sw = .{
                        .rs1 = @enumFromInt(raw.rs1),
                        .rs2 = @enumFromInt(raw.rs2),
                        .imm = imm,
                    } };
                },
                0b000 => {
                    return .{ .sb = .{
                        .rs1 = @enumFromInt(raw.rs1),
                        .rs2 = @enumFromInt(raw.rs2),
                        .imm = imm,
                    } };
                },
                0b001 => {
                    return .{ .sh = .{
                        .rs1 = @enumFromInt(raw.rs1),
                        .rs2 = @enumFromInt(raw.rs2),
                        .imm = imm,
                    } };
                },
                else => return error.UnsupportedInstruction,
            }
        },
        else => return error.UnsupportedOpcode,
    }
}

pub fn main() !void {
    const words = [_]u32{
        0x00c00093, // addi x1,  x0, 12
        0x00500113, // addi x2,  x0, 5
        0x002081b3, // add  x3,  x1, x2
        0x40208233, // sub  x4,  x1, x2
        0x0020f2b3, // and  x5,  x1, x2
        0x00a0f313, // andi x6,  x1, 10
        0x0020e3b3, // or   x7,  x1, x2
        0x00816413, // ori  x8,  x2, 8
        0x0020c4b3, // xor  x9,  x1, x2
        0x00f0c513, // xori x10, x1, 15
        0xfff00593, // addi x11, x0, -1
        0x05a5f613, // andi x12, x11, 0x5a
        0x05506693, // ori  x13, x0, 0x55
        0xfff6c713, // xori x14, x13, -1
        0x00309793, // slli x15, x1, 3
        0x00475813, // srli x16, x14, 4
        0x40475893, // srai x17, x14, 4
        0x00209933, // sll  x18, x1, x2
        0x002759b3, // srl  x19, x14, x2
        0x40275a33, // sra  x20, x14, x2
        0x08000a93, // addi x21, x0, 128
        0x00eaa223, // sw   x14, 4(x21)
        0x004aab03, // lw   x22, 4(x21)
        0xfedaae23, // sw   x13, -4(x21)
        0xffcaab83, // lw   x23, -4(x21)
    };

    var buf: [words.len * 4]u8 = undefined;
    const memory = toBytes(&words, &buf);

    var cpu = Cpu{};
    try cpu.loadProgramAt(0, memory);
    try cpu.run(words.len);
    cpu.dumpRegisters();
}

fn toBytes(words: []const u32, bytes: []u8) []u8 {
    for (words, 0..) |word, i| {
        std.mem.writeInt(
            u32,
            bytes[i * 4 ..][0..4],
            word,
            .little,
        );
    }

    return bytes[0..];
}
