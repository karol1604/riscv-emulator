const std = @import("std");

const Cpu = struct {
    regs: [32]u32 = .{0} ** 32,
    /// Program counter
    pc: u32 = 0,
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

    pub fn format(self: Instruction, writer: *std.Io.Writer) !void {
        switch (self) {
            .addi => |instr| {
                try writer.print("addi {s}, {s}, {d}", .{
                    @tagName(instr.rd),
                    @tagName(instr.rs1),
                    instr.imm,
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

fn opcode(instruction: u32) u7 {
    return @intCast(instruction & 0b1111111);
}

fn decode(instruction: u32) !Instruction {
    const op = opcode(instruction);

    switch (op) {
        0b0010011 => {
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
        else => return error.UnsupportedOpcode,
    }
}

pub fn main() !void {
    const instr: u32 = 0x00708113; // addi x1, x0, 5
    std.debug.print("Instruction: 0x{x:0>8} => 0b{b:0>32}\n", .{ instr, instr });
    std.debug.print("Opcode: 0b{b:0>7}\n", .{opcode(instr)});
    std.debug.print("Decoded instruction: {any}\n", .{try decode(instr)});

    const final = try decode(instr);
    std.debug.print("Final instruction: {f}\n", .{final});
}
