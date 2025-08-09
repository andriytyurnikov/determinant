/// Zicsr extension: Control and Status Register instructions (6 variants).

const fmt = @import("../format.zig");
const Format = fmt.Format;

pub const Opcode = enum {
    CSRRW,
    CSRRS,
    CSRRC,
    CSRRWI,
    CSRRSI,
    CSRRCI,

    pub fn meta(comptime self: Opcode) fmt.Meta {
        return .{ .name_str = @tagName(self), .fmt = .I };
    }

    pub fn name(self: Opcode) []const u8 {
        return fmt.opcodeName(Opcode, self);
    }

    pub fn format(self: Opcode) Format {
        return fmt.opcodeFormat(Opcode, self);
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

pub const CsrResult = struct {
    rd_val: ?u32 = null,
};

pub const Csr = struct {
    mscratch: u32 = 0,

    /// Execute a CSR instruction. `src_val` is the register value or zimm.
    /// `src_nonzero` indicates whether the rs1 field (register number or zimm) is nonzero,
    /// per the RISC-V spec — this controls whether CSRRS/CSRRC attempt a write.
    pub fn execute(self: *Csr, op: Opcode, cycle_count: u64, csr_addr: u12, src_val: u32, rd_nonzero: bool, src_nonzero: bool) !CsrResult {
        return switch (op) {
            .CSRRW, .CSRRWI => blk: {
                var result = CsrResult{};
                if (rd_nonzero) {
                    result.rd_val = try self.read(cycle_count, csr_addr);
                }
                try self.write(csr_addr, src_val);
                break :blk result;
            },
            .CSRRS, .CSRRSI => blk: {
                const old = try self.read(cycle_count, csr_addr);
                if (src_nonzero) {
                    try self.write(csr_addr, old | src_val);
                }
                break :blk .{ .rd_val = old };
            },
            .CSRRC, .CSRRCI => blk: {
                const old = try self.read(cycle_count, csr_addr);
                if (src_nonzero) {
                    try self.write(csr_addr, old & ~src_val);
                }
                break :blk .{ .rd_val = old };
            },
        };
    }

    pub fn read(self: *const Csr, cycle_count: u64, addr: u12) !u32 {
        return switch (addr) {
            // cycle (0xC00) and instret (0xC02) are aliased: this VM retires exactly
            // 1 instruction per cycle, so the counters are always identical.
            0xC00, 0xC02 => @truncate(cycle_count),
            // cycleh (0xC80) and instreth (0xC82) — upper 32 bits, same aliasing.
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
