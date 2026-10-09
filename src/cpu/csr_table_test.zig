//! Every CSR number × every CSR instruction × (rd = x0 or not) × (source zero or not),
//! checked against a model of SEMANTICS.md, "CSRs":
//!   - readable: cycle, instret (0xC00, 0xC02), cycleh, instreth (0xC80, 0xC82), mscratch;
//!   - writable: mscratch only;
//!   - CSRRW/CSRRWI read only when rd != x0 and always write; CSRRS/CSRRC and the
//!     immediate forms always read and write only when the source (rs1 / uimm) is non-zero;
//!   - an access the CSR does not allow raises IllegalInstruction and changes nothing.

const std = @import("std");
const cpu_mod = @import("../cpu.zig");
const h = @import("../instructions/test_helpers.zig");

const Cpu = cpu_mod.CpuType(4096, .{ .decode_cache_entries = 0 });

const Op = enum(u3) { csrrw = 0b001, csrrs = 0b010, csrrc = 0b011, csrrwi = 0b101, csrrsi = 0b110, csrrci = 0b111 };

const cycles: u64 = 0x0000_0005_0000_0007; // distinct high and low halves
const mscratch_init: u32 = 0x1234_5678;
const rs1_val: u32 = 0x0F0F_00F0;
const uimm: u5 = 0b10110;
const rd_sentinel: u32 = 0xDEAD_BEEF;

fn readable(n: u12) bool {
    return switch (n) {
        0xC00, 0xC02, 0xC80, 0xC82, 0x340 => true,
        else => false,
    };
}

fn readValue(n: u12) u32 {
    return switch (n) {
        0xC00, 0xC02 => @truncate(cycles),
        0xC80, 0xC82 => @truncate(cycles >> 32),
        0x340 => mscratch_init,
        else => unreachable,
    };
}

const Expected = union(enum) {
    illegal,
    ok: struct { rd: u32, mscratch: u32 },
};

/// The model: what the instruction must do, from SEMANTICS.md alone.
fn expected(op: Op, n: u12, rd: u5, src_nonzero: bool) Expected {
    const immediate = @intFromEnum(op) >= 0b101;
    const src: u32 = if (!src_nonzero) 0 else if (immediate) uimm else rs1_val;
    const reads = switch (op) {
        .csrrw, .csrrwi => rd != 0,
        else => true,
    };
    const writes = switch (op) {
        .csrrw, .csrrwi => true,
        else => src_nonzero,
    };
    if (reads and !readable(n)) return .illegal;
    if (writes and n != 0x340) return .illegal;
    const old = if (readable(n)) readValue(n) else 0;
    const new_mscratch = if (n != 0x340 or !writes) mscratch_init else switch (op) {
        .csrrw, .csrrwi => src,
        .csrrs, .csrrsi => old | src,
        .csrrc, .csrrci => old & ~src,
    };
    return .{ .ok = .{ .rd = if (rd == 0) 0 else if (reads) old else rd_sentinel, .mscratch = new_mscratch } };
}

test "CSR table: all 4096 CSR numbers x 6 instructions x rd x source" {
    const cpu = try std.testing.allocator.create(Cpu);
    defer std.testing.allocator.destroy(cpu);
    cpu.reset();
    var checked: usize = 0;
    var legal: usize = 0;
    for (0..4096) |n_usize| {
        const n: u12 = @intCast(n_usize);
        for (std.enums.values(Op)) |op| {
            for ([_]u5{ 0, 5 }) |rd| {
                for ([_]bool{ false, true }) |src_nonzero| {
                    const immediate = @intFromEnum(op) >= 0b101;
                    // rs1 field: a register for the plain forms, the uimm for the I forms
                    const rs1_field: u5 = if (!src_nonzero) 0 else if (immediate) uimm else 6;
                    cpu.pc = 0;
                    cpu.cycle_count = cycles;
                    cpu.csrs.mscratch = mscratch_init;
                    cpu.writeReg(5, rd_sentinel);
                    cpu.writeReg(6, rs1_val);
                    std.mem.writeInt(u32, cpu.memory[0..4], h.encodeCsr(@intFromEnum(op), rd, rs1_field, n), .little);

                    const want = expected(op, n, rd, src_nonzero);
                    const got = cpu.step();
                    switch (want) {
                        .illegal => {
                            _ = got catch |err| {
                                try std.testing.expectEqual(error.IllegalInstruction, err);
                                try std.testing.expectEqual(@as(u32, 0), cpu.pc);
                                try std.testing.expectEqual(cycles, cpu.cycle_count);
                                try std.testing.expectEqual(mscratch_init, cpu.csrs.mscratch);
                                try std.testing.expectEqual(rd_sentinel, cpu.readReg(5));
                                checked += 1;
                                continue;
                            };
                            std.debug.print("{s} csr=0x{x:0>3} rd=x{d} src={}: expected IllegalInstruction\n", .{ @tagName(op), n, rd, src_nonzero });
                            return error.TestExpectedError;
                        },
                        .ok => |w| {
                            _ = got catch |err| {
                                std.debug.print("{s} csr=0x{x:0>3} rd=x{d} src={}: unexpected {s}\n", .{ @tagName(op), n, rd, src_nonzero, @errorName(err) });
                                return err;
                            };
                            if (rd != 0) try std.testing.expectEqual(w.rd, cpu.readReg(5));
                            try std.testing.expectEqual(w.mscratch, cpu.csrs.mscratch);
                            try std.testing.expectEqual(@as(u32, 4), cpu.pc);
                            try std.testing.expectEqual(cycles + 1, cpu.cycle_count);
                            checked += 1;
                            legal += 1;
                        },
                    }
                }
            }
        }
    }
    try std.testing.expectEqual(@as(usize, 4096 * 6 * 2 * 2), checked);
    // Legal combinations: the five readable CSRs with every non-writing form, plus
    // mscratch with the writing ones; everything else traps.
    try std.testing.expect(legal > 0 and legal < 200);
}
