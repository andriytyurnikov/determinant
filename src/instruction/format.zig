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

/// Generic name accessor for any Opcode enum with a pub `meta()` returning a type with `name_str`.
pub fn opcodeName(comptime OpcodeType: type, self: OpcodeType) []const u8 {
    return switch (self) { inline else => |v| comptime OpcodeType.meta(v).name_str };
}

/// Generic format accessor for any Opcode enum with a pub `meta()` returning a type with `fmt`.
pub fn opcodeFormat(comptime OpcodeType: type, self: OpcodeType) Format {
    return switch (self) { inline else => |v| comptime OpcodeType.meta(v).fmt };
}
