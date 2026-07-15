const std = @import("std");

// zig fmt: off
pub const Register = enum(u5) {
    x0 = 0, x1, x2, x3, x4, x5, x6, x7,
    x8, x9, x10, x11, x12, x13, x14, x15, x16, x17,
    x18, x19, x20, x21, x22, x23, x24, x25, x26, x27, x28, x29, x30, x31,
};
// zig fmt: on

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

const RawInstructionTypeSB = packed struct(u32) {
    opcode: u7,
    imm11: u1,
    imm4_1: u4,
    funct3: u3,
    rs1: u5,
    rs2: u5,
    imm10_5: u6,
    imm12: u1,
};

const RawInstructionTypeUJ = packed struct(u32) {
    opcode: u7,
    rd: u5,
    imm19_12: u8,
    imm11: u1,
    imm10_1: u10,
    imm20: u1,
};

const RawInstructionTypeU = packed struct(u32) {
    opcode: u7,
    rd: u5,
    imm31_12: u20,
};

pub const Instruction = union(enum) {
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
    beq: struct {
        rs1: Register,
        rs2: Register,
        imm: i13,
    },
    bne: struct {
        rs1: Register,
        rs2: Register,
        imm: i13,
    },
    blt: struct {
        rs1: Register,
        rs2: Register,
        imm: i13,
    },
    bltu: struct {
        rs1: Register,
        rs2: Register,
        imm: i13,
    },
    bge: struct {
        rs1: Register,
        rs2: Register,
        imm: i13,
    },
    bgeu: struct {
        rs1: Register,
        rs2: Register,
        imm: i13,
    },
    jal: struct {
        rd: Register,
        imm: i21,
    },
    jalr: struct {
        rd: Register,
        rs1: Register,
        imm: i12,
    },
    lui: struct {
        rd: Register,
        imm: u20,
    },
    auipc: struct {
        rd: Register,
        imm: u20,
    },
    ebreak,

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
            .beq => |instr| {
                try writer.print("beq {s}, {s}, {d}", .{
                    @tagName(instr.rs1),
                    @tagName(instr.rs2),
                    instr.imm,
                });
            },
            .bne => |instr| {
                try writer.print("bne {s}, {s}, {d}", .{
                    @tagName(instr.rs1),
                    @tagName(instr.rs2),
                    instr.imm,
                });
            },
            .blt => |instr| {
                try writer.print("blt {s}, {s}, {d}", .{
                    @tagName(instr.rs1),
                    @tagName(instr.rs2),
                    instr.imm,
                });
            },
            .bltu => |instr| {
                try writer.print("bltu {s}, {s}, {d}", .{
                    @tagName(instr.rs1),
                    @tagName(instr.rs2),
                    instr.imm,
                });
            },
            .bge => |instr| {
                try writer.print("bge {s}, {s}, {d}", .{
                    @tagName(instr.rs1),
                    @tagName(instr.rs2),
                    instr.imm,
                });
            },
            .bgeu => |instr| {
                try writer.print("bgeu {s}, {s}, {d}", .{
                    @tagName(instr.rs1),
                    @tagName(instr.rs2),
                    instr.imm,
                });
            },
            .jal => |instr| {
                try writer.print("jal {s}, {d}", .{
                    @tagName(instr.rd),
                    instr.imm,
                });
            },
            .jalr => |instr| {
                try writer.print("jalr {s}, {d}({s})", .{
                    @tagName(instr.rd),
                    instr.imm,
                    @tagName(instr.rs1),
                });
            },
            .lui => |instr| {
                try writer.print("lui {s}, {d}", .{
                    @tagName(instr.rd),
                    instr.imm,
                });
            },
            .auipc => |instr| {
                try writer.print("auipc {s}, {d}", .{
                    @tagName(instr.rd),
                    instr.imm,
                });
            },
            .ebreak => {
                try writer.print("ebreak", .{});
            },
        }
    }
};

const OpCode = enum(u7) {
    op_imm = 0b0010011,
    op_reg = 0b0110011,
    load = 0b0000011,
    store = 0b0100011,
    branch = 0b1100011,
    jal = 0b1101111,
    jalr = 0b1100111,
    lui = 0b0110111,
    auipc = 0b0010111,
    system = 0b1110011,
    _,
};

fn opcode(instruction: u32) OpCode {
    const op: u7 = @intCast(instruction & 0b1111111);
    return @enumFromInt(op);
}

pub fn decode(instruction: u32) !Instruction {
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
        .branch => {
            const raw: RawInstructionTypeSB = @bitCast(instruction);
            const imm = decodeBranchImmediate(raw);
            switch (raw.funct3) {
                0b000 => {
                    return .{ .beq = .{
                        .rs1 = @enumFromInt(raw.rs1),
                        .rs2 = @enumFromInt(raw.rs2),
                        .imm = imm,
                    } };
                },
                0b001 => {
                    return .{ .bne = .{
                        .rs1 = @enumFromInt(raw.rs1),
                        .rs2 = @enumFromInt(raw.rs2),
                        .imm = imm,
                    } };
                },
                0b100 => {
                    return .{ .blt = .{
                        .rs1 = @enumFromInt(raw.rs1),
                        .rs2 = @enumFromInt(raw.rs2),
                        .imm = imm,
                    } };
                },
                0b110 => {
                    return .{ .bltu = .{
                        .rs1 = @enumFromInt(raw.rs1),
                        .rs2 = @enumFromInt(raw.rs2),
                        .imm = imm,
                    } };
                },
                0b101 => {
                    return .{ .bge = .{
                        .rs1 = @enumFromInt(raw.rs1),
                        .rs2 = @enumFromInt(raw.rs2),
                        .imm = imm,
                    } };
                },
                0b111 => {
                    return .{ .bgeu = .{
                        .rs1 = @enumFromInt(raw.rs1),
                        .rs2 = @enumFromInt(raw.rs2),
                        .imm = imm,
                    } };
                },
                else => return error.UnsupportedInstruction,
            }
        },
        .jal => {
            const raw: RawInstructionTypeUJ = @bitCast(instruction);
            const imm_bits: u21 =
                (@as(u21, raw.imm20) << 20) |
                (@as(u21, raw.imm19_12) << 12) |
                (@as(u21, raw.imm11) << 11) |
                (@as(u21, raw.imm10_1) << 1);
            return .{ .jal = .{
                .rd = @enumFromInt(raw.rd),
                .imm = @bitCast(imm_bits),
            } };
        },
        .jalr => {
            const raw: RawInstructionTypeI = @bitCast(instruction);
            if (raw.funct3 != 0b000) return error.UnsupportedInstruction;

            return .{ .jalr = .{
                .rd = @enumFromInt(raw.rd),
                .rs1 = @enumFromInt(raw.rs1),
                .imm = raw.imm,
            } };
        },
        .lui => {
            const raw: RawInstructionTypeU = @bitCast(instruction);
            return .{ .lui = .{
                .rd = @enumFromInt(raw.rd),
                .imm = raw.imm31_12,
            } };
        },
        .auipc => {
            const raw: RawInstructionTypeU = @bitCast(instruction);
            return .{ .auipc = .{
                .rd = @enumFromInt(raw.rd),
                .imm = raw.imm31_12,
            } };
        },
        .system => {
            const raw: RawInstructionTypeI = @bitCast(instruction);
            switch (raw.funct3) {
                0b000 => {
                    if (raw.imm != 1) return error.UnsupportedInstruction;
                    if (raw.rs1 != 0) return error.UnsupportedInstruction;
                    if (raw.rd != 0) return error.UnsupportedInstruction;
                    return .{ .ebreak = {} };
                },
                else => return error.UnsupportedInstruction,
            }
        },
        else => return error.UnsupportedOpcode,
    }
}

fn decodeBranchImmediate(raw: RawInstructionTypeSB) i13 {
    const bits: u13 =
        (@as(u13, raw.imm12) << 12) |
        (@as(u13, raw.imm11) << 11) |
        (@as(u13, raw.imm10_5) << 5) |
        (@as(u13, raw.imm4_1) << 1);
    return @bitCast(bits);
}

fn decodeStoreImmediate(raw: RawInstructionTypeS) i12 {
    const bits: u12 = (@as(u12, raw.imm11_5) << 5) | raw.imm4_0;
    return @bitCast(bits);
}
