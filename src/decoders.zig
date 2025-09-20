//! Namespace for decoders — re-exports branch, lut, expand, registry, bitfields.

pub const branch = @import("decoders/branch.zig");
pub const lut = @import("decoders/lut.zig");
pub const expand = @import("decoders/expand.zig");
pub const registry = @import("decoders/registry.zig");
pub const bitfields = @import("decoders/bitfields.zig");

/// Canonical DecodeError — defined in bitfields.zig, re-exported by both decoders.
pub const DecodeError = bitfields.DecodeError;

comptime {
    if (branch.DecodeError != lut.DecodeError)
        @compileError("DecodeError definitions diverged between decoders");
}

test {
    _ = branch;
    _ = lut;
    _ = expand;
    _ = registry;
    _ = bitfields;
}
