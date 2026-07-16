const std = @import("std");

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

/// Loads an ELF file from the given path and returns its contents as a byte slice.
/// Caller must free the returned slice.
pub fn loadElf(io: std.Io, alloc: std.mem.Allocator, path: []const u8) ![]const u8 {
    const file = try std.Io.Dir.cwd().openFile(io, path, .{});
    defer file.close(io);

    const elf_data = try alloc.alloc(u8, try file.length(io));
    // defer alloc.free(elf_data);

    var reader = file.reader(io, elf_data);
    reader.interface.readSliceAll(elf_data) catch |err| switch (err) {
        error.ReadFailed => return reader.err.?,
        else => return err,
    };

    return elf_data;
}

pub fn parseELFHeader(elf_data: []const u8) !Elf32Ehdr {
    const ident = elf_data[0..16].*;
    if (ident[0] != 0x7F or ident[1] != 'E' or ident[2] != 'L' or ident[3] != 'F') {
        return error.InvalidELFMagic;
    }
    if (ident[4] != 1) { // EI_CLASS: 1 = 32-bit
        return error.Only32BitELFSupported;
    }
    if (elf_data.len < 52) { // ELF header size for 32-bit is 52 bytes
        return error.ELFHeaderTooShort;
    }
    if (ident[5] != 1) { // EI_DATA: 1 = little-endian
        return error.OnlyLittleEndianELFSupported;
    }

    // NOTE: for now, we only support little-endian 32-bit ELF files
    // we can expand this later
    const e_type = std.mem.readInt(u16, elf_data[16..][0..2], .little);
    const e_machine = std.mem.readInt(u16, elf_data[18..][0..2], .little);
    const e_version = std.mem.readInt(u32, elf_data[20..][0..4], .little);
    const e_entry = std.mem.readInt(u32, elf_data[24..][0..4], .little);
    const e_phoff = std.mem.readInt(u32, elf_data[28..][0..4], .little);
    const e_shoff = std.mem.readInt(u32, elf_data[32..][0..4], .little);
    const e_flags = std.mem.readInt(u32, elf_data[36..][0..4], .little);
    const e_ehsize = std.mem.readInt(u16, elf_data[40..][0..2], .little);
    const e_phentsize = std.mem.readInt(u16, elf_data[42..][0..2], .little);
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
