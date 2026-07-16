const std = @import("std");
const Cpu = @import("cpu").Cpu;
const elf = @import("elf");

const elf_header_size = 52;
const program_header_size = 32;

fn writeU16(bytes: []u8, offset: usize, value: u16) void {
    std.mem.writeInt(u16, bytes[offset..][0..2], value, .little);
}

fn writeU32(bytes: []u8, offset: usize, value: u32) void {
    std.mem.writeInt(u32, bytes[offset..][0..4], value, .little);
}

fn writeElfHeader(bytes: []u8, entry: u32, program_header_count: u16) void {
    bytes[0..4].* = .{ 0x7f, 'E', 'L', 'F' };
    bytes[4] = 1; // ELFCLASS32
    bytes[5] = 1; // ELFDATA2LSB
    bytes[6] = 1; // EV_CURRENT

    writeU16(bytes, 16, 2); // ET_EXEC
    writeU16(bytes, 18, 243); // EM_RISCV
    writeU32(bytes, 20, 1); // EV_CURRENT
    writeU32(bytes, 24, entry);
    writeU32(bytes, 28, elf_header_size);
    writeU16(bytes, 40, elf_header_size);
    writeU16(bytes, 42, program_header_size);
    writeU16(bytes, 44, program_header_count);
}

fn writeProgramHeader(
    bytes: []u8,
    index: usize,
    kind: u32,
    file_offset: u32,
    virtual_address: u32,
    file_size: u32,
    memory_size: u32,
) void {
    const offset = elf_header_size + index * program_header_size;
    writeU32(bytes, offset, kind);
    writeU32(bytes, offset + 4, file_offset);
    writeU32(bytes, offset + 8, virtual_address);
    writeU32(bytes, offset + 12, virtual_address);
    writeU32(bytes, offset + 16, file_size);
    writeU32(bytes, offset + 20, memory_size);
    writeU32(bytes, offset + 24, 0b111);
    writeU32(bytes, offset + 28, 4);
}

test "ELF loader loads multiple PT_LOAD segments and sets the entry point" {
    var bytes = [_]u8{0} ** 192;
    writeElfHeader(&bytes, 0x40, 2);
    writeProgramHeader(&bytes, 0, 1, 128, 0x40, 4, 4);
    writeProgramHeader(&bytes, 1, 1, 132, 0x80, 3, 3);
    bytes[128..135].* = .{ 0x13, 0x00, 0x00, 0x00, 0xaa, 0xbb, 0xcc };

    var cpu = Cpu{};
    try elf.loadElfIntoCpu(std.testing.allocator, &cpu, &bytes);

    try std.testing.expectEqual(@as(u32, 0x40), cpu.pc);
    try std.testing.expectEqualSlices(u8, bytes[128..132], cpu.memory[0x40..0x44]);
    try std.testing.expectEqualSlices(u8, bytes[132..135], cpu.memory[0x80..0x83]);
}

test "ELF loader zero-fills the part of a segment not present in the file" {
    var bytes = [_]u8{0} ** 160;
    writeElfHeader(&bytes, 0x20, 1);
    writeProgramHeader(&bytes, 0, 1, 128, 0x20, 3, 8);
    bytes[128..131].* = .{ 0xde, 0xad, 0xbe };

    var cpu = Cpu{};
    @memset(cpu.memory[0x20..0x28], 0xff);
    try elf.loadElfIntoCpu(std.testing.allocator, &cpu, &bytes);

    try std.testing.expectEqualSlices(u8, &.{ 0xde, 0xad, 0xbe }, cpu.memory[0x20..0x23]);
    try std.testing.expectEqualSlices(u8, &.{ 0, 0, 0, 0, 0 }, cpu.memory[0x23..0x28]);
}

test "ELF loader ignores program headers that are not PT_LOAD" {
    var bytes = [_]u8{0} ** 160;
    writeElfHeader(&bytes, 0, 1);
    writeProgramHeader(&bytes, 0, 4, 128, 0x30, 4, 4); // PT_NOTE
    bytes[128..132].* = .{ 1, 2, 3, 4 };

    var cpu = Cpu{};
    @memset(cpu.memory[0x30..0x34], 0xaa);
    try elf.loadElfIntoCpu(std.testing.allocator, &cpu, &bytes);

    try std.testing.expectEqualSlices(u8, &.{ 0xaa, 0xaa, 0xaa, 0xaa }, cpu.memory[0x30..0x34]);
}

test "ELF loader rejects a segment whose file size exceeds its memory size" {
    var bytes = [_]u8{0} ** 160;
    writeElfHeader(&bytes, 0, 1);
    writeProgramHeader(&bytes, 0, 1, 128, 0x20, 8, 4);

    var cpu = Cpu{};
    try std.testing.expectError(
        error.InvalidProgramHeader,
        elf.loadElfIntoCpu(std.testing.allocator, &cpu, &bytes),
    );
}

test "ELF loader rejects a segment outside the ELF file" {
    var bytes = [_]u8{0} ** 160;
    writeElfHeader(&bytes, 0, 1);
    writeProgramHeader(&bytes, 0, 1, std.math.maxInt(u32) - 3, 0x20, 8, 8);

    var cpu = Cpu{};
    try std.testing.expectError(
        error.ProgramHeaderOutOfBounds,
        elf.loadElfIntoCpu(std.testing.allocator, &cpu, &bytes),
    );
}

test "ELF loader rejects a segment outside CPU memory" {
    var bytes = [_]u8{0} ** 160;
    writeElfHeader(&bytes, 0, 1);
    writeProgramHeader(&bytes, 0, 1, 128, std.math.maxInt(u32) - 1, 4, 4);

    var cpu = Cpu{};
    try std.testing.expectError(
        error.ProgramHeaderOutOfBounds,
        elf.loadElfIntoCpu(std.testing.allocator, &cpu, &bytes),
    );
}

test "ELF loader rejects a truncated program header table" {
    var bytes = [_]u8{0} ** 64;
    writeElfHeader(&bytes, 0, 1);

    var cpu = Cpu{};
    try std.testing.expectError(
        error.ProgramHeadersOutOfBounds,
        elf.loadElfIntoCpu(std.testing.allocator, &cpu, &bytes),
    );
}
