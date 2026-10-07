const std = @import("std");
const Io = std.Io;
const main_mod = @import("../main.zig");
const det = @import("determinant");

const alloc = std.testing.allocator;

fn expectContains(haystack: []const u8, needle: []const u8) !void {
    if (std.mem.indexOf(u8, haystack, needle) == null) {
        std.debug.print("\nExpected output to contain: \"{s}\"\nActual output:\n{s}\n", .{ needle, haystack });
        return error.TestExpectedEqual;
    }
}

test "runDemo: shows the program, its result and the stored word" {
    if (det.Cpu.mem_size < main_mod.demo_min_memory) return error.SkipZigTest;
    var out_aw: Io.Writer.Allocating = .init(alloc);
    defer out_aw.deinit();
    var err_aw: Io.Writer.Allocating = .init(alloc);
    defer err_aw.deinit();
    try std.testing.expectEqual(main_mod.ExitStatus.ok, try main_mod.runDemo(&out_aw.writer, &err_aw.writer, null, null));

    const output = out_aw.written();

    try expectContains(output, "Demo");
    try expectContains(output, "ADDI");
    try expectContains(output, "ADD");
    try expectContains(output, "SW");
    try expectContains(output, "ECALL");
    try expectContains(output, "ecall after 5 cycles");
    try expectContains(output, "x1 = 100");
    try expectContains(output, "x2 = 10");
    try expectContains(output, "x3 = 110");
    try expectContains(output, "Memory[100] = 110");
}

test "runDemo: reproducible output" {
    if (det.Cpu.mem_size < main_mod.demo_min_memory) return error.SkipZigTest;
    var out1: Io.Writer.Allocating = .init(alloc);
    defer out1.deinit();
    var err1: Io.Writer.Allocating = .init(alloc);
    defer err1.deinit();
    try std.testing.expectEqual(main_mod.ExitStatus.ok, try main_mod.runDemo(&out1.writer, &err1.writer, null, null));

    var out2: Io.Writer.Allocating = .init(alloc);
    defer out2.deinit();
    var err2: Io.Writer.Allocating = .init(alloc);
    defer err2.deinit();
    try std.testing.expectEqual(main_mod.ExitStatus.ok, try main_mod.runDemo(&out2.writer, &err2.writer, null, null));

    try std.testing.expectEqualStrings(out1.written(), out2.written());
}

test "runDemo: memory too small for the demo fails cleanly" {
    if (det.Cpu.mem_size >= main_mod.demo_min_memory) return error.SkipZigTest;
    var out_aw: Io.Writer.Allocating = .init(alloc);
    defer out_aw.deinit();
    var err_aw: Io.Writer.Allocating = .init(alloc);
    defer err_aw.deinit();
    const result = main_mod.runDemo(&out_aw.writer, &err_aw.writer, null, null);
    if (det.Cpu.mem_size < main_mod.demo_program.len) {
        // The program itself does not fit: a configuration (usage) error
        try std.testing.expectError(error.UserError, result);
    } else {
        // The program loads, but its store to address 100 faults
        try std.testing.expectEqual(main_mod.ExitStatus.vm_fault, try result);
    }
    try std.testing.expect(err_aw.written().len > 0);
}

test "demo_program: every instruction decodes as its comment says" {
    // Checks the real bytes. The second word once had 0x0A/0xA0 transposed,
    // which encodes ADDI x2, x20, 0 instead of ADDI x2, x0, 10.
    const Expect = struct { op: det.Opcode, rd: u5 = 0, rs1: u5 = 0, rs2: u5 = 0, imm: i32 = 0 };
    const want = [_]Expect{
        .{ .op = .{ .i = .ADDI }, .rd = 1, .rs1 = 0, .imm = 100 },
        .{ .op = .{ .i = .ADDI }, .rd = 2, .rs1 = 0, .imm = 10 },
        .{ .op = .{ .i = .ADD }, .rd = 3, .rs1 = 1, .rs2 = 2 },
        .{ .op = .{ .i = .SW }, .rs1 = 1, .rs2 = 3, .imm = 0 },
        .{ .op = .{ .i = .ECALL } },
    };
    try std.testing.expectEqual(want.len * 4, main_mod.demo_program.len);
    for (want, 0..) |w, i| {
        const raw = std.mem.readInt(u32, main_mod.demo_program[4 * i ..][0..4], .little);
        const inst = try det.decode(raw);
        try std.testing.expectEqual(w.op, inst.op);
        try std.testing.expectEqual(w.rd, inst.rd);
        try std.testing.expectEqual(w.rs1, inst.rs1);
        try std.testing.expectEqual(w.rs2, inst.rs2);
        try std.testing.expectEqual(w.imm, inst.imm);
    }
}
