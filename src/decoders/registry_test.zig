const std = @import("std");
const reg = @import("registry.zig");
const decoder = @import("branch.zig");
const instructions = @import("../instructions.zig");
const Opcode = instructions.Opcode;

test "registry: no two entries overlap" {
    for (reg.registry, 0..) |a, i| {
        for (reg.registry[i + 1 ..]) |b| {
            const common = a.mask() & b.mask();
            if ((a.match() ^ b.match()) & common == 0) {
                std.debug.print("overlap: {s} and {s}\n", .{ a.op.name(), b.op.name() });
                return error.TestUnexpectedResult;
            }
        }
    }
}

test "registry: every Opcode variant has exactly one entry" {
    inline for (@typeInfo(Opcode).@"union".fields) |uf| {
        inline for (@typeInfo(uf.type).@"enum".fields) |ef| {
            const op = @unionInit(Opcode, uf.name, @enumFromInt(ef.value));
            var n: usize = 0;
            for (reg.registry) |e| {
                if (std.meta.eql(e.op, op)) n += 1;
            }
            if (n != 1) {
                std.debug.print("{s}.{s}: {d} registry entries\n", .{ uf.name, ef.name, n });
                return error.TestUnexpectedResult;
            }
        }
    }
}

test "registry: lookup finds each entry's own encoding" {
    for (reg.registry) |e| {
        const found = reg.lookup(e.match()) orelse return error.TestUnexpectedResult;
        try std.testing.expectEqual(e.op, found.op);
    }
}

test "registry: every entry decodes to its op and operands, with random free bits" {
    var prng = std.Random.DefaultPrng.init(0x5EED_D3C0);
    const random = prng.random();
    for (reg.registry) |e| {
        for (0..256) |_| {
            const raw = (random.int(u32) & ~e.mask()) | e.match();
            const got = decoder.decode(raw) catch |err| {
                std.debug.print("0x{x:0>8} ({s}): {s}\n", .{ raw, e.op.name(), @errorName(err) });
                return err;
            };
            try std.testing.expectEqualDeep(reg.instruction(e, raw), got);
        }
    }
}

/// Decode `raw` and check it against the registry: legal exactly when an entry matches,
/// and then equal to that entry's instruction.
fn expectAgreesWithRegistry(raw: u32) !void {
    if (reg.lookup(raw)) |e| {
        const got = decoder.decode(raw) catch |err| {
            std.debug.print("0x{x:0>8}: registry says {s}, decoder says {s}\n", .{ raw, e.op.name(), @errorName(err) });
            return err;
        };
        try std.testing.expectEqualDeep(reg.instruction(e, raw), got);
    } else if (decoder.decode(raw)) |got| {
        std.debug.print("0x{x:0>8}: not in the registry, decoder says {s}\n", .{ raw, got.op.name() });
        return error.TestUnexpectedResult;
    } else |_| {}
}

test "registry: decoder accepts exactly the registry's encodings (structured sweep)" {
    // Every value of the identifying fields — opcode[6:2], funct3, funct7 — with the rs2
    // values that some entry constrains, their neighbours, and the extremes. The full
    // 2^30 sweep of 32-bit encodings is `zig build verify-decoder`.
    const rs2_values = [_]u5{ 0, 1, 2, 3, 4, 5, 6, 7, 8, 23, 24, 25, 31 };
    for (0..32) |op_hi| {
        const opcode7: u32 = (@as(u32, @intCast(op_hi)) << 2) | 0b11;
        for (0..8) |f3| {
            for (0..128) |f7| {
                for (rs2_values) |rs2| {
                    const raw = opcode7 | (@as(u32, @intCast(f3)) << 12) | (@as(u32, rs2) << 20) | (@as(u32, @intCast(f7)) << 25);
                    try expectAgreesWithRegistry(raw);
                    if (opcode7 == 0b1110011) {
                        // SYSTEM: rd and rs1 are identifying for ECALL/EBREAK
                        try expectAgreesWithRegistry(raw | (1 << 7));
                        try expectAgreesWithRegistry(raw | (1 << 15));
                        try expectAgreesWithRegistry(raw | (31 << 7) | (31 << 15));
                    }
                }
            }
        }
    }
}
