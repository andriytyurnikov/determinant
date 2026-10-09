const std = @import("std");
const reg = @import("registry.zig");
const lut = @import("lut.zig");
const branch = @import("branch.zig");

/// Encode an entry with every field it does not constrain set to zero.
fn encodeEntry(e: reg.Entry) u32 {
    var raw: u32 = e.opcode7;
    if (e.f3) |v| raw |= @as(u32, v) << 12;
    if (e.f7) |v| raw |= @as(u32, v) << 25;
    if (e.rs2_eq) |v| raw |= @as(u32, v) << 20;
    if (e.f5) |v| raw |= @as(u32, v) << 27;
    if (e.f12) |v| raw |= @as(u32, v) << 20;
    return raw;
}

test "registry: every entry decodes to its own opcode (both decoders)" {
    for (reg.registry) |e| {
        const raw = encodeEntry(e);
        try std.testing.expectEqual(e.op, (try lut.decode(raw)).op);
        try std.testing.expectEqual(e.op, (try branch.decode(raw)).op);
    }
}
