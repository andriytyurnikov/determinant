/// Zicsr extension: Control and Status Register instructions (6 variants).
/// This module does NOT import instruction.zig — it is imported BY it.

const Format = @import("format.zig").Format;

pub const Opcode = enum {
    CSRRW,
    CSRRS,
    CSRRC,
    CSRRWI,
    CSRRSI,
    CSRRCI,

    pub fn format(self: Opcode) Format {
        _ = self;
        return .I;
    }
};

/// Decode a SYSTEM instruction's funct3 into a Zicsr opcode.
/// Returns null for funct3 values that belong to other SYSTEM instructions
/// (0b000 = ECALL/EBREAK, 0b100 = reserved).
pub fn decodeSystem(f3: u3) ?Opcode {
    return switch (f3) {
        0b001 => .CSRRW,
        0b010 => .CSRRS,
        0b011 => .CSRRC,
        0b101 => .CSRRWI,
        0b110 => .CSRRSI,
        0b111 => .CSRRCI,
        else => null,
    };
}

pub const Csr = struct {
    mscratch: u32 = 0,

    pub fn read(self: *const Csr, cycle_count: u64, addr: u12) !u32 {
        return switch (addr) {
            0xC00, 0xC02 => @truncate(cycle_count),
            0xC80, 0xC82 => @truncate(cycle_count >> 32),
            0x340 => self.mscratch,
            else => error.IllegalInstruction,
        };
    }

    pub fn write(self: *Csr, addr: u12, value: u32) !void {
        if ((addr >> 10) & 0b11 == 0b11) return error.IllegalInstruction;
        switch (addr) {
            0x340 => self.mscratch = value,
            else => return error.IllegalInstruction,
        }
    }
};

test {
    _ = @import("zicsr_test.zig");
}
