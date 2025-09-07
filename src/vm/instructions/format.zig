//! Format enum (R/I/S/B/U/J), Meta struct, and comptime opcode name/format helpers.

/// RV32 instruction formats.
pub const Format = enum {
    R,
    I,
    S,
    B,
    U,
    J,
};

/// Per-opcode metadata returned by each extension's comptime `meta()` function.
pub const Meta = struct {
    name_str: []const u8,
    fmt: Format,
};

/// Return the human-readable name for any extension Opcode value.
///
/// Uses `inline else` to expand the switch at comptime — each arm calls the
/// extension's `meta()` method on a comptime-known enum value, producing a
/// direct lookup with zero runtime branches.
pub fn opcodeName(comptime OpcodeType: type, self: OpcodeType) []const u8 {
    return switch (self) {
        inline else => |v| comptime OpcodeType.meta(v).name_str,
    };
}

/// Return the instruction format (R/I/S/B/U/J) for any extension Opcode value.
///
/// Same `inline else` comptime dispatch as `opcodeName` — the compiler
/// generates a perfect jump table from enum discriminant to format constant.
pub fn opcodeFormat(comptime OpcodeType: type, self: OpcodeType) Format {
    return switch (self) {
        inline else => |v| comptime OpcodeType.meta(v).fmt,
    };
}
