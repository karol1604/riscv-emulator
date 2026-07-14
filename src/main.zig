const std = @import("std");
const builtin = @import("builtin");

pub const Cpu = struct {
    regs: [32]u32 = .{0} ** 32,
    /// Program counter
    pc: u32 = 0,

    /// Executes a program represented as raw bytes
    pub fn execute(self: *Cpu, program: []const u8) !void {
        while (@as(usize, @intCast(self.pc)) < program.len) {
            const raw = try self.fetchInstruction(program);
            const instr = try decode(raw);
            if (!builtin.is_test) {
                std.debug.print("0x{x:0>8}: {f}\n", .{ self.pc, instr });
            }
            self.executeInstruction(instr);
            self.pc +%= 4;
        }
    }

    pub fn dumpRegisters(self: *const Cpu) void {
        for (self.regs, 0..) |reg, i| {
            std.debug.print("x{d}: 0x{x:0>8} => 0b{b:0>32} => {d}\n", .{ i, reg, reg, reg });
        }
    }

    fn executeInstruction(self: *Cpu, instr: Instruction) void {
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
        }
    }

    fn fetchInstruction(self: *const Cpu, memory: []const u8) !u32 {
        const pc: usize = @intCast(self.pc);

        if (pc + 4 > memory.len) return error.OutOfBounds;
        if (pc % 4 != 0) return error.UnalignedAccess;

        return std.mem.readInt(u32, memory[pc..][0..4], .little);
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
        }
    }
};

const RawInstructionTypeI = packed struct(u32) {
    opcode: u7,
    rd: u5,
    funct3: u3,
    rs1: u5,
    imm: i12,

    pub fn format(self: RawInstructionTypeI, writer: *std.Io.Writer) !void {
        try writer.print("RawInstructionTypeI {{ opcode: 0b{b:0>7}, rd: {d}, funct3: 0b{b:0>3}, rs1: {d}, imm: {d} }}", .{
            self.opcode,
            self.rd,
            self.funct3,
            self.rs1,
            self.imm,
        });
    }
};

const RawInstructionTypeR = packed struct(u32) {
    opcode: u7,
    rd: u5,
    funct3: u3,
    rs1: u5,
    rs2: u5,
    funct7: u7,

    pub fn format(self: RawInstructionTypeR, writer: *std.Io.Writer) !void {
        try writer.print("RawInstructionTypeR {{ opcode: 0b{b:0>7}, rd: {d}, funct3: 0b{b:0>3}, rs1: {d}, rs2: {d}, funct7: 0b{b:0>7} }}", .{
            self.opcode,
            self.rd,
            self.funct3,
            self.rs1,
            self.rs2,
            self.funct7,
        });
    }
};

const OpCode = enum(u7) {
    op_imm = 0b0010011,
    op_reg = 0b0110011,
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
                else => return error.UnsupportedInstruction,
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
                else => return error.UnsupportedInstruction,
            }
        },
        else => return error.UnsupportedOpcode,
    }
}

pub fn main() !void {
    const words = [_]u32{
        0x00c00093, // addi x1,  x0, 12    => x1  = 12
        0x00500113, // addi x2,  x0, 5     => x2  = 5

        0x002081b3, // add   x3,  x1, x2    => x3  = 17
        0x40208233, // sub   x4,  x1, x2    => x4  = 7

        0x0020f2b3, // and   x5,  x1, x2    => x5  = 4
        0x00a0f313, // andi  x6,  x1, 10    => x6  = 8

        0x0020e3b3, // or    x7,  x1, x2    => x7  = 13
        0x00816413, // ori   x8,  x2, 8     => x8  = 13

        0x0020c4b3, // xor   x9,  x1, x2    => x9  = 9
        0x00f0c513, // xori  x10, x1, 15    => x10 = 3

        // sign-extension checks
        0xfff00593, // addi  x11, x0, -1    => x11 = 0xffffffff
        0x05a5f613, // andi  x12, x11, 0x5a => x12 = 0x5a
        0x05506693, // ori   x13, x0, 0x55  => x13 = 0x55
        0xfff6c713, // xori  x14, x13, -1   => x14 = 0xffffffaa
    };

    var buf: [words.len * 4]u8 = undefined;
    const memory = toBytes(&words, &buf);

    var cpu = Cpu{};
    try cpu.execute(memory);
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
