const std = @import("std");

const Cpu = struct {
    regs: [32]u32 = .{0} ** 32,
    /// Program counter
    pc: u32 = 0,

    pub fn execute(self: *Cpu, program: []const u32) !void {
        for (program) |instr| {
            const decoded = try decode(instr);
            std.debug.print("{f}\n", .{decoded});
            self.executeInstruction(decoded);

            self.regs[0] = 0; // x0 is always zero
            self.pc += 4; // increment program counter by 4 bytes (size of instruction)
        }
    }

    pub fn dumpRegisters(self: *Cpu) void {
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
        }
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
                else => return error.UnsupportedInstruction,
            }
        },
        // else => return error.UnsupportedOpcode,
    }
}

pub fn main() !void {
    const program = [_]u32{
        0x00500093, // addi x1, x0, 5
        0x00708113, // addi x2, x1, 7
        0x002081b3, // add  x3, x1, x2
        0x40118233, // sub  x4, x3, x1
    };

    var cpu = Cpu{};
    try cpu.execute(program[0..]);
    cpu.dumpRegisters();
}
