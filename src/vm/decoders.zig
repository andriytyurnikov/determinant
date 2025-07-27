pub const branch_decoder = @import("decoders/branch_decoder/branch_decoder.zig");
pub const lut_decoder = @import("decoders/lut_decoder/lut_decoder.zig");
pub const registry = @import("decoders/registry.zig");
pub const bitfields = @import("decoders/bitfields.zig");

/// Canonical DecodeError — both decoders must define the same error set.
pub const DecodeError = lut_decoder.DecodeError;

comptime {
    if (branch_decoder.DecodeError != lut_decoder.DecodeError)
        @compileError("DecodeError definitions diverged between decoders");
}
