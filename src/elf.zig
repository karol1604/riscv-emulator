const std = @import("std");
const cpu_mod = @import("cpu");

pub const Elf32Ehdr = struct {
    e_ident: [16]u8,
    e_type: u16,
    e_machine: u16,
    e_version: u32,
    e_entry: u32,
    e_phoff: u32,
    e_shoff: u32,
    e_flags: u32,
    e_ehsize: u16,
    e_phentsize: u16,
    e_phnum: u16,
    e_shentsize: u16,
    e_shnum: u16,
    e_shstrndx: u16,
};

pub const Elf32Phdr = struct {
    p_type: u32,
    p_offset: u32,
    p_vaddr: u32,
    p_paddr: u32,
    p_filesz: u32,
    p_memsz: u32,
    p_flags: u32,
    p_align: u32,
};

/// Loads an ELF file from the given path and returns its contents as a byte slice.
/// Caller must free the returned slice.
pub fn loadElf(io: std.Io, alloc: std.mem.Allocator, path: []const u8) ![]const u8 {
    const file = try std.Io.Dir.cwd().openFile(io, path, .{});
    defer file.close(io);

    const elf_data = try alloc.alloc(u8, try file.length(io));
    errdefer alloc.free(elf_data);

    var reader = file.reader(io, elf_data);
    reader.interface.readSliceAll(elf_data) catch |err| switch (err) {
        error.ReadFailed => return reader.err.?,
        else => return err,
    };

    return elf_data;
}

pub fn parseELFHeader(elf_data: []const u8) !Elf32Ehdr {
    if (elf_data.len < 52) { // ELF header size for 32-bit is 52 bytes
        return error.ELFHeaderTooShort;
    }

    const ident = elf_data[0..16].*;
    if (ident[0] != 0x7F or ident[1] != 'E' or ident[2] != 'L' or ident[3] != 'F') {
        return error.InvalidELFMagic;
    }
    if (ident[4] != 1) { // EI_CLASS: 1 = 32-bit
        return error.Only32BitELFSupported;
    }
    if (ident[5] != 1) { // EI_DATA: 1 = little-endian
        return error.OnlyLittleEndianELFSupported;
    }
    if (ident[6] != 1) { // EI_VERSION: 1 = original version
        return error.UnsupportedELFVersion;
    }

    // NOTE: for now, we only support little-endian 32-bit ELF files
    // we can expand this later
    const e_type = std.mem.readInt(u16, elf_data[16..][0..2], .little);
    if (e_type != 2) { // ET_EXEC: 2 = executable file
        return error.OnlyExecutableELFSupported;
    }

    const e_machine = std.mem.readInt(u16, elf_data[18..][0..2], .little);
    if (e_machine != 243) { // EM_RISCV: 243 = RISC-V
        return error.OnlyRISCVELFSupported;
    }

    const e_version = std.mem.readInt(u32, elf_data[20..][0..4], .little);
    if (e_version != 1) { // EV_CURRENT: 1 = current version
        return error.UnsupportedELFVersion;
    }

    const e_entry = std.mem.readInt(u32, elf_data[24..][0..4], .little);
    const e_phoff = std.mem.readInt(u32, elf_data[28..][0..4], .little);
    const e_shoff = std.mem.readInt(u32, elf_data[32..][0..4], .little);
    const e_flags = std.mem.readInt(u32, elf_data[36..][0..4], .little);
    const e_ehsize = std.mem.readInt(u16, elf_data[40..][0..2], .little);
    if (e_ehsize != 52) { // ELF header size for 32-bit is 52 bytes
        return error.InvalidELFHeaderSize;
    }

    const e_phentsize = std.mem.readInt(u16, elf_data[42..][0..2], .little);
    if (e_phentsize != 32) { // Program header size for 32-bit is 32 bytes
        return error.InvalidELFProgramHeaderSize;
    }

    const e_phnum = std.mem.readInt(u16, elf_data[44..][0..2], .little);
    const e_shentsize = std.mem.readInt(u16, elf_data[46..][0..2], .little);
    const e_shnum = std.mem.readInt(u16, elf_data[48..][0..2], .little);
    const e_shstrndx = std.mem.readInt(u16, elf_data[50..][0..2], .little);

    return Elf32Ehdr{
        .e_ident = ident,
        .e_type = e_type,
        .e_machine = e_machine,
        .e_version = e_version,
        .e_entry = e_entry,
        .e_phoff = e_phoff,
        .e_shoff = e_shoff,
        .e_flags = e_flags,
        .e_ehsize = e_ehsize,
        .e_phentsize = e_phentsize,
        .e_phnum = e_phnum,
        .e_shentsize = e_shentsize,
        .e_shnum = e_shnum,
        .e_shstrndx = e_shstrndx,
    };
}

/// Parses the program headers from the given ELF data and returns them as an array of Elf32Phdr.
/// Caller must free the returned array.
pub fn parseProgramHeaders(
    alloc: std.mem.Allocator,
    elf_data: []const u8,
    elf_header: Elf32Ehdr,
) ![]Elf32Phdr {
    const phoff: usize = @intCast(elf_header.e_phoff);
    const phentsize: usize = @intCast(elf_header.e_phentsize);
    const phnum: usize = @intCast(elf_header.e_phnum);
    const table_size = std.math.mul(usize, phnum, phentsize) catch {
        return error.ProgramHeadersOutOfBounds;
    };

    if (phoff > elf_data.len or table_size > elf_data.len - phoff) {
        return error.ProgramHeadersOutOfBounds;
    }

    var phdrs = try alloc.alloc(Elf32Phdr, elf_header.e_phnum);
    errdefer alloc.free(phdrs);
    for (0..elf_header.e_phnum) |i| {
        const offset = phoff + (i * phentsize);

        const p_type = std.mem.readInt(u32, elf_data[offset..][0..4], .little);
        const p_offset = std.mem.readInt(u32, elf_data[offset + 4 ..][0..4], .little);
        const p_vaddr = std.mem.readInt(u32, elf_data[offset + 8 ..][0..4], .little);
        const p_paddr = std.mem.readInt(u32, elf_data[offset + 12 ..][0..4], .little);
        const p_filesz = std.mem.readInt(u32, elf_data[offset + 16 ..][0..4], .little);
        const p_memsz = std.mem.readInt(u32, elf_data[offset + 20 ..][0..4], .little);
        const p_flags = std.mem.readInt(u32, elf_data[offset + 24 ..][0..4], .little);
        const p_align = std.mem.readInt(u32, elf_data[offset + 28 ..][0..4], .little);

        phdrs[i] = Elf32Phdr{
            .p_type = p_type,
            .p_offset = p_offset,
            .p_vaddr = p_vaddr,
            .p_paddr = p_paddr,
            .p_filesz = p_filesz,
            .p_memsz = p_memsz,
            .p_flags = p_flags,
            .p_align = p_align,
        };
    }

    return phdrs;
}

pub fn loadElfIntoCpu(alloc: std.mem.Allocator, cpu: *cpu_mod.Cpu, elf_data: []const u8) !void {
    const elf_header = try parseELFHeader(elf_data);
    const elf_program_headers = try parseProgramHeaders(alloc, elf_data, elf_header);
    defer alloc.free(elf_program_headers);

    try loadIntoCpu(cpu, elf_data, elf_header, elf_program_headers);
}

fn loadIntoCpu(
    cpu: *cpu_mod.Cpu,
    elf_data: []const u8,
    elf_header: Elf32Ehdr,
    elf_program_headers: []Elf32Phdr,
) !void {
    for (elf_program_headers) |ph| {
        if (ph.p_type != 1) continue; // not PT_LOAD
        if (ph.p_filesz > ph.p_memsz) return error.InvalidProgramHeader;

        const file_offset: usize = @intCast(ph.p_offset);
        const file_size: usize = @intCast(ph.p_filesz);
        if (file_offset > elf_data.len or file_size > elf_data.len - file_offset) {
            return error.ProgramHeaderOutOfBounds;
        }

        const memory_start: usize = @intCast(ph.p_vaddr);
        const memory_size: usize = @intCast(ph.p_memsz);
        if (memory_start > cpu.memory.len or memory_size > cpu.memory.len - memory_start) {
            return error.ProgramHeaderOutOfBounds;
        }

        const file_end = file_offset + file_size;
        const initialized_end = memory_start + file_size;
        const memory_end = memory_start + memory_size;
        const segment = elf_data[file_offset..file_end];
        try cpu.loadProgramAt(ph.p_vaddr, segment);
        cpu.zeroOutMemory(initialized_end, memory_end);
    }

    cpu.pc = elf_header.e_entry;
}
