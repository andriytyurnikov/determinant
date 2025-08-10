pub const branch_decoder = @import("decoders/branch_decoder/branch_decoder.zig");
pub const lut_decoder = @import("decoders/lut_decoder/lut_decoder.zig");
pub const expand = @import("decoders/expand.zig");
pub const registry = @import("decoders/registry.zig");
pub const bitfields = @import("decoders/bitfields.zig");

/// Canonical DecodeError — defined in bitfields.zig, re-exported by both decoders.
pub const DecodeError = bitfields.DecodeError;

comptime {
    if (branch_decoder.DecodeError != lut_decoder.DecodeError)
        @compileError("DecodeError definitions diverged between decoders");
}

test {
    _ = branch_decoder;
    _ = lut_decoder;
    _ = expand;
    _ = registry;
    _ = bitfields;
}
