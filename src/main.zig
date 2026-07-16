const std = @import("std");
const Cpu = @import("cpu").Cpu;
const elf = @import("elf.zig");

pub fn main(init: std.process.Init) !void {
    std.debug.print("=== Instruction demo ===\n", .{});

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
        0x20000a93, // addi x21, x0, 512
        0x00eaa223, // sw   x14, 4(x21)
        0x004aab03, // lw   x22, 4(x21)
        0xfedaae23, // sw   x13, -4(x21)
        0xffcaab83, // lw   x23, -4(x21)
        0x00100c13, // addi x24, x0, 1
        0x00200c93, // addi x25, x0, 2
        0x019c0463, // beq  x24, x25, 8 (not taken)
        0x00a00d13, // addi x26, x0, 10
        0x019c1463, // bne  x24, x25, 8
        0x06300d93, // addi x27, x0, 99 (skipped)
        0x00b00d93, // addi x27, x0, 11
        0x019c4463, // blt  x24, x25, 8
        0x06300e13, // addi x28, x0, 99 (skipped)
        0x00c00e13, // addi x28, x0, 12
        0x018cd463, // bge  x25, x24, 8
        0x06300e93, // addi x29, x0, 99 (skipped)
        0x00d00e93, // addi x29, x0, 13
        0x00ec6463, // bltu x24, x14, 8
        0x06300f13, // addi x30, x0, 99 (skipped)
        0x00e00f13, // addi x30, x0, 14
        0x01877463, // bgeu x14, x24, 8
        0x06300f93, // addi x31, x0, 99 (skipped)
        0x00f00f93, // addi x31, x0, 15
    };

    var buf: [words.len * 4]u8 = undefined;
    const memory = toBytes(&words, &buf);

    var cpu = Cpu{};
    try cpu.loadProgramAt(0, memory);
    try cpu.run(words.len - 5); // five taken branches each skip one instruction
    cpu.dumpRegisters();

    std.debug.print("\n=== Loop demo ===\n", .{});

    const loop_words = [_]u32{
        0x00000093, // addi x1, x0, 0   (counter = 0)
        0x00a00113, // addi x2, x0, 10  (limit = 10)
        0x00108093, // addi x1, x1, 1   (counter += 1)
        0xfe20cee3, // blt  x1, x2, -4  (loop while counter < limit)
    };

    var loop_buf: [loop_words.len * 4]u8 = undefined;
    const loop_memory = toBytes(&loop_words, &loop_buf);

    var loop_cpu = Cpu{};
    try loop_cpu.loadProgramAt(0, loop_memory);
    try loop_cpu.run(2 + (2 * 10));

    std.debug.print("counter: {d}, limit: {d}, pc: 0x{x:0>8}\n", .{
        loop_cpu.regs[1],
        loop_cpu.regs[2],
        loop_cpu.pc,
    });
    loop_cpu.dumpRegisters();

    std.debug.print("\n=== Function call demo ===\n", .{});

    const function_words = [_]u32{
        0x00700513, // addi a0, x0, 7      (argument = 7)
        0x00c000ef, // jal  ra, 12          (call function at 0x10)
        0x00150593, // addi x11, a0, 1      (runs after return)
        0x00c0006f, // jal  x0, 12          (skip function body)
        0x00550513, // addi a0, a0, 5       (function: return a0 + 5)
        0x00008067, // jalr x0, 0(ra)        (return)
        0x00050613, // addi x12, a0, 0      (end marker/result copy)
    };

    var function_buf: [function_words.len * 4]u8 = undefined;
    const function_memory = toBytes(&function_words, &function_buf);

    var function_cpu = Cpu{};
    try function_cpu.loadProgramAt(0, function_memory);
    try function_cpu.run(7);

    std.debug.print("return address: 0x{x:0>8}, result: {d}, after return: {d}, pc: 0x{x:0>8}\n", .{
        function_cpu.regs[1],
        function_cpu.regs[10],
        function_cpu.regs[11],
        function_cpu.pc,
    });

    var debug_allocator: std.heap.DebugAllocator(.{}) = .init;
    defer _ = debug_allocator.deinit();

    const allocator = debug_allocator.allocator();

    const io = init.io;
    const file = try std.Io.Dir.cwd().openFile(io, "programs/program5.bin", .{});
    defer file.close(io);

    const program = try allocator.alloc(u8, try file.length(io));
    defer allocator.free(program);

    var reader = file.reader(io, program);
    reader.interface.readSliceAll(program) catch |err| switch (err) {
        error.ReadFailed => return reader.err.?,
        else => return err,
    };

    var cpu_bin = Cpu{};
    try cpu_bin.loadProgramAt(0, program);

    std.debug.print("\n=== Binary file demo ===\n", .{});
    try cpu_bin.runUntilHalt(1000);
    cpu_bin.dumpRegisters();

    const elf_data = try elf.loadElf(io, allocator, "program5.elf");
    defer allocator.free(elf_data);

    const elf_header = try elf.parseELFHeader(elf_data);
    std.debug.print("\n elf header: {any}\n", .{elf_header});

    const elf_program_headers = try elf.parseProgramHeaders(allocator, elf_data, elf_header);
    defer allocator.free(elf_program_headers);

    var cpu_elf = Cpu{};
    try elf.loadElfIntoCpu(allocator, &cpu_elf, elf_data);

    std.debug.print("\n=== ELF file demo ===\n", .{});
    try cpu_elf.runUntilHalt(1000);
    cpu_elf.dumpRegisters();
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
