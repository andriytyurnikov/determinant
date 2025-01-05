const std = @import("std");
const det = @import("determinant");

pub fn main() !void {
    var stdout_buffer: [4096]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
    const stdout = &stdout_writer.interface;

    try stdout.print("Determinant — RV32I Decoder Demo\n\n", .{});

    // Hardcoded 5-instruction RV32I program:
    //   ADDI x1, x0, 5      — x1 = 5
    //   ADDI x2, x0, 10     — x2 = 10
    //   ADD  x3, x1, x2     — x3 = x1 + x2
    //   SW   x3, 0(x1)      — mem[x1] = x3
    //   ECALL                — system call
    const program = [_]u32{
        0x00500093, // ADDI x1, x0, 5
        0x00A00113, // ADDI x2, x0, 10
        0x002081B3, // ADD  x3, x1, x2
        0x0030A023, // SW   x3, 0(x1)
        0x00000073, // ECALL
    };

    for (program, 0..) |word, i| {
        const addr = i * 4;
        if (det.decode(word)) |inst| {
            try stdout.print("  0x{X:0>4}: ", .{addr});
            try printInstruction(stdout, inst);
            try stdout.print("\n", .{});
        } else |err| {
            try stdout.print("  0x{X:0>4}: ??? (error: {s})\n", .{ addr, @errorName(err) });
        }
    }

    try stdout.print("\nDecoded {d} instructions.\n", .{program.len});
    try stdout.flush();
}

fn printInstruction(stdout: anytype, inst: det.Instruction) !void {
    const op_name = @tagName(inst.op);
    switch (inst.op.format()) {
        .R => try stdout.print("{s} x{d}, x{d}, x{d}", .{ op_name, inst.rd, inst.rs1, inst.rs2 }),
        .I => switch (inst.op) {
            .LB, .LH, .LW, .LBU, .LHU, .JALR => try stdout.print("{s} x{d}, {d}(x{d})", .{ op_name, inst.rd, inst.imm, inst.rs1 }),
            .ECALL, .EBREAK => try stdout.print("{s}", .{op_name}),
            else => try stdout.print("{s} x{d}, x{d}, {d}", .{ op_name, inst.rd, inst.rs1, inst.imm }),
        },
        .S => try stdout.print("{s} x{d}, {d}(x{d})", .{ op_name, inst.rs2, inst.imm, inst.rs1 }),
        .B => try stdout.print("{s} x{d}, x{d}, {d}", .{ op_name, inst.rs1, inst.rs2, inst.imm }),
        .U => try stdout.print("{s} x{d}, 0x{X}", .{ op_name, inst.rd, @as(u32, @bitCast(inst.imm)) >> 12 }),
        .J => try stdout.print("{s} x{d}, {d}", .{ op_name, inst.rd, inst.imm }),
    }
}
