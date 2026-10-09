//! Namespace for the instruction decoder: decode() plus its parts — branch (the decoder),
//! expand (RV32C expansion), registry (the specification it is tested against) and
//! bitfields (field extraction).

pub const branch = @import("decoders/branch.zig");
pub const expand = @import("decoders/expand.zig");
pub const registry = @import("decoders/registry.zig");
pub const bitfields = @import("decoders/bitfields.zig");

/// Decode a 32-bit word or a zero-extended 16-bit RV32C halfword into an Instruction.
pub const decode = branch.decode;

/// Error returned for encodings that are not legal instructions.
pub const DecodeError = bitfields.DecodeError;

test {
    _ = branch;
    _ = expand;
    _ = registry;
    _ = bitfields;
}
