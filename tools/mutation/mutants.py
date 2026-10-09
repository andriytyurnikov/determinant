# Mutant catalogue for Determinant's mutation tests (see README.md).
#
# Each mutant is one small, plausible bug:
#   dict(id=..., file=<path relative to the tree>, desc=..., edits=[(orig, repl), ...])
# The driver applies the edits in order. Each `orig` must occur EXACTLY ONCE in the
# file as it stands when that edit is applied, so include enough surrounding text to
# make it unique; `mutate.py --check` fails loudly otherwise. Anchors are plain
# substrings and may span lines ("\n" plus the exact indentation).
#
# Anchored against commit a64af47 (first written against c907c18; DC04, MN03 and HA05
# re-anchored since). After source changes, run `mutate.py --check` and re-anchor
# whatever it reports.
#
# PORTED: the catalogue of the October 2026 review (written against 39df644 with line
# numbers), re-anchored with the old IDs. Re-targeted because the code changed:
#   C17, C18, C22, C23  readWord/writeWord now share checkWordAccess(); these inline a
#                       private, faulty copy of the check into one of the two methods
#   C27, C28, C29       x0 is hardwired in three places now (readReg's branch,
#                       writeReg's regs[0] restore, the zeroing in step()); C27/C28 drop
#                       one each as before, C29 drops all three
#   C37                 SC.W now checks its address first, which C37 used to inject;
#                       it now removes that check (the pre-fix behaviour)
# Dropped, because the LUT decoder (src/decoders/lut.zig) was deleted:
#   D08 D12 D13 D14 D24 D25 D26 D27. D08, D12, D25 and D24 reappear in the branch
#   decoder (now the only decoder) as BR04, BR05, BR06 and BR07; D27 and D14 (the shamt
#   operand rule) as RG03 and RG04 in registry.instruction(); D13 and D26 (LUT table
#   generation) have no counterpart.
#
# The CLI mutants (MN, HA05, CL, AR, SO, RP, TR, DS, DM, UN) were re-anchored or written
# for the CLI rewrite (docs/design/cli.md), and LD14 for loader.segments().
#
# NEW: mutants for code added since 39df644 (decode cache, state encoding, registry as
# specification, checkWordAccess, SC.W ordering, loadProgram and the reservation,
# reserved encodings, regs[0] zeroing, CLI exit statuses, host API), and since c907c18
# (host calls HC, ELF loading LD, snapshots SN, CLI loading and exit CL).

EXEC = "src/cpu/exec_i.zig"
CPU = "src/cpu.zig"
STATE = "src/cpu/state.zig"
CSR = "src/instructions/zicsr.zig"
M = "src/instructions/rv32m.zig"
A = "src/instructions/rv32a.zig"
ZBA = "src/instructions/zba.zig"
ZBB = "src/instructions/zbb.zig"
ZBS = "src/instructions/zbs.zig"
REG = "src/decoders/registry.zig"
BF = "src/decoders/bitfields.zig"
BR = "src/decoders/branch.zig"
IMM = "src/instructions/rv32i/rv32c/imm.zig"
EXP = "src/instructions/rv32i/rv32c/expand.zig"
RVC = "src/instructions/rv32i/rv32c.zig"
MAIN = "src/main.zig"
ARGS = "src/main/args.zig"
LOADC = "src/main/load.zig"
REPORT = "src/main/report.zig"
DISASM = "src/main/disasm.zig"
DUMP = "src/main/dump.zig"
UNITS = "src/main/units.zig"
HC = "src/hostcall.zig"
LD = "src/loader.zig"

S32 = "@as(i32, @bitCast(rs1_val)) < @as(i32, @bitCast(rs2_val))"
SC_CHECK = "try checkWordAccess(addr);\n                    // reservation is guaranteed"
STEP_ZERO = "self.regs[0] = 0;\n            const rs1_val"
WRITE_REG = "self.regs[reg] = value;\n            self.regs[0] = 0;"
NEXT_PC = "var next_pc: u32 = self.pc +% inst_size;"
READ_WORD = "try checkWordAccess(addr);\n            return std.mem.readInt(u32"
WRITE_WORD = "try checkWordAccess(addr);\n            std.mem.writeInt(u32"
DECODE_CACHED = "if (slot.raw != raw) slot.* = try decodeFn(raw);"


def inline_word_check(align, bound_op, tail):
    """A private copy of checkWordAccess() for one method, with a faulty check."""
    return (f"if (addr % {align} != 0) return error.MisalignedAccess;\n"
            f"            if (addr {bound_op} mem_size - 4) return error.AddressOutOfBounds;\n"
            f"            {tail}")


PORTED = [
    # ---------------- exec_i.zig (RV32I execute) ----------------
    dict(id="I01", file=EXEC, desc="SRA -> logical shift", edits=[("@bitCast(@as(i32, @bitCast(rs1_val)) >> @truncate(rs2_val & 0x1F))", "rs1_val >> @truncate(rs2_val & 0x1F)")]),
    dict(id="I02", file=EXEC, desc="SRAI -> logical shift", edits=[("@bitCast(@as(i32, @bitCast(rs1_val)) >> @truncate(imm_u & 0x1F))", "rs1_val >> @truncate(imm_u & 0x1F)")]),
    dict(id="I03", file=EXEC, desc="SLT signed -> unsigned compare", edits=[(".SLT => cpu.writeReg(rd, if (" + S32, ".SLT => cpu.writeReg(rd, if (rs1_val < rs2_val")]),
    dict(id="I04", file=EXEC, desc="SLTI signed -> unsigned compare", edits=[("if (@as(i32, @bitCast(rs1_val)) < imm)", "if (rs1_val < imm_u)")]),
    dict(id="I05", file=EXEC, desc="SLTIU compares against imm without sign-extension", edits=[(".SLTIU => cpu.writeReg(rd, if (rs1_val < imm_u)", ".SLTIU => cpu.writeReg(rd, if (rs1_val < (imm_u & 0xFFF))")]),
    dict(id="I06", file=EXEC, desc="SLL shift mask 0x1F -> 0x3F", edits=[(".SLL => cpu.writeReg(rd, rs1_val << @truncate(rs2_val & 0x1F))", ".SLL => cpu.writeReg(rd, rs1_val << @truncate(rs2_val & 0x3F))")]),
    dict(id="I07", file=EXEC, desc="SRL shift mask 0x1F -> 0x0F", edits=[(".SRL => cpu.writeReg(rd, rs1_val >> @truncate(rs2_val & 0x1F))", ".SRL => cpu.writeReg(rd, rs1_val >> @truncate(rs2_val & 0x0F))")]),
    dict(id="I08", file=EXEC, desc="BGE >= -> >", edits=[(">= @as(i32", "> @as(i32")]),
    dict(id="I09", file=EXEC, desc="BLTU unsigned -> signed", edits=[("if (rs1_val < rs2_val) next_pc", "if (" + S32 + ") next_pc")]),
    dict(id="I10", file=EXEC, desc="BGEU >= -> >", edits=[("rs1_val >= rs2_val", "rs1_val > rs2_val")]),
    dict(id="I11", file=EXEC, desc="BLT < -> <=", edits=[("if (" + S32 + ") next_pc", "if (" + S32.replace(" < ", " <= ") + ") next_pc")]),
    dict(id="I12", file=EXEC, desc="BGE signed -> unsigned", edits=[("@as(i32, @bitCast(rs1_val)) >= @as(i32, @bitCast(rs2_val))", "rs1_val >= rs2_val")]),
    dict(id="I13", file=EXEC, desc="BNE target relative to next_pc instead of pc", edits=[("if (rs1_val != rs2_val) next_pc.* = cpu.pc +% imm_u", "if (rs1_val != rs2_val) next_pc.* = next_pc.* +% imm_u")]),
    dict(id="I14", file=EXEC, desc="JALR missing & 0xFFFFFFFE", edits=[("(rs1_val +% imm_u) & 0xFFFFFFFE", "(rs1_val +% imm_u)")]),
    dict(id="I15", file=EXEC, desc="JALR writes rd before computing target (rd==rs1 case)", edits=[("const return_addr = cpu.pc +% inst_size;", "const return_addr = cpu.pc +% inst_size;\n            cpu.writeReg(rd, return_addr);")]),
    dict(id="I16", file=EXEC, desc="JAL link = pc+4 instead of pc+inst_size", edits=[("cpu.writeReg(rd, cpu.pc +% inst_size);", "cpu.writeReg(rd, cpu.pc +% 4);")]),
    dict(id="I17", file=EXEC, desc="JALR link = pc+4 instead of pc+inst_size", edits=[("const return_addr = cpu.pc +% inst_size;", "const return_addr = cpu.pc +% 4;")]),
    dict(id="I18", file=EXEC, desc="AUIPC uses next_pc instead of pc", edits=[(".AUIPC => cpu.writeReg(rd, cpu.pc +% imm_u)", ".AUIPC => cpu.writeReg(rd, next_pc.* +% imm_u)")]),
    dict(id="I19", file=EXEC, desc="LB zero-extends", edits=[("@bitCast(@as(i32, @as(i8, @bitCast(byte))))", "@as(u32, byte)")]),
    dict(id="I20", file=EXEC, desc="LH zero-extends", edits=[("@bitCast(@as(i32, @as(i16, @bitCast(half))))", "@as(u32, half)")]),
    dict(id="I21", file=EXEC, desc="LBU sign-extends", edits=[("cpu.writeReg(rd, @as(u32, byte));", "cpu.writeReg(rd, @bitCast(@as(i32, @as(i8, @bitCast(byte)))));")]),
    dict(id="I22", file=EXEC, desc="LHU sign-extends", edits=[("cpu.writeReg(rd, @as(u32, half));", "cpu.writeReg(rd, @bitCast(@as(i32, @as(i16, @bitCast(half)))));")]),
    dict(id="I23", file=EXEC, desc="SB stores a halfword (clobbers neighbour byte)", edits=[("try cpu.writeByte(addr, @truncate(rs2_val));", "try cpu.writeHalfword(addr, @truncate(rs2_val));")]),
    dict(id="I24", file=EXEC, desc="SH truncates to a byte (upper byte stored as 0)", edits=[("try cpu.writeHalfword(addr, @truncate(rs2_val));", "try cpu.writeHalfword(addr, @as(u8, @truncate(rs2_val)));")]),
    dict(id="I25", file=EXEC, desc="ADD non-wrapping (+% -> +)", edits=[(".ADD => cpu.writeReg(rd, rs1_val +% rs2_val)", ".ADD => cpu.writeReg(rd, rs1_val + rs2_val)")]),
    dict(id="I26", file=EXEC, desc="ANDI uses zero-extended 12-bit imm", edits=[(".ANDI => cpu.writeReg(rd, rs1_val & imm_u)", ".ANDI => cpu.writeReg(rd, rs1_val & (imm_u & 0xFFF))")]),
    dict(id="I27", file=EXEC, desc="ECALL returns .ebreak", edits=[(".ECALL => return .ecall,", ".ECALL => return .ebreak,")]),
    dict(id="I28", file=EXEC, desc="SLTU < -> <=", edits=[(".SLTU => cpu.writeReg(rd, if (rs1_val < rs2_val)", ".SLTU => cpu.writeReg(rd, if (rs1_val <= rs2_val)")]),

    # ---------------- cpu.zig ----------------
    dict(id="C01", file=CPU, desc="writeByte does not invalidate reservation", edits=[("self.memory[addr] = value;\n            self.invalidateReservation(addr);", "self.memory[addr] = value;\n            {}")]),
    dict(id="C02", file=CPU, desc="writeHalfword does not invalidate reservation", edits=[("std.mem.writeInt(u16, self.memory[addr..][0..2], value, .little);\n            self.invalidateReservation(addr);", "std.mem.writeInt(u16, self.memory[addr..][0..2], value, .little);\n            {}")]),
    dict(id="C03", file=CPU, desc="writeWord does not invalidate reservation", edits=[("std.mem.writeInt(u32, self.memory[addr..][0..4], value, .little);\n            self.invalidateReservation(addr);", "std.mem.writeInt(u32, self.memory[addr..][0..4], value, .little);\n            {}")]),
    dict(id="C04", file=CPU, desc="invalidateReservation exact-address match instead of word match", edits=[("if ((addr & 0xFFFFFFFC) == res_addr) {", "if (addr == res_addr) {")]),
    dict(id="C05", file=CPU, desc="SC.W does not clear reservation (failure path; success path cleared by writeWord)", edits=[("self.writeReg(rd, 1); // failure\n                    }\n                    self.reservation = null;", "self.writeReg(rd, 1); // failure\n                    }\n                    {}")]),
    dict(id="C06", file=CPU, desc="SC.W success path skips explicit reservation clear (early return)", edits=[("self.writeReg(rd, 0); // success", "self.writeReg(rd, 0);\n                        return; // success")]),
    dict(id="C07", file=CPU, desc="LR.W does not set reservation", edits=[("self.reservation = addr;", "{}")]),
    dict(id="C08", file=CPU, desc="SC.W success/failure codes swapped", edits=[("self.writeReg(rd, 0); // success", "self.writeReg(rd, 1); // success"), ("self.writeReg(rd, 1); // failure", "self.writeReg(rd, 0); // failure")]),
    dict(id="C09", file=CPU, desc="AMO writes rd before memory write", edits=[("const old = try self.readWord(addr);", "const old = try self.readWord(addr);\n                    self.writeReg(rd, old);")]),
    dict(id="C10", file=CPU, desc="AMO returns new value in rd", edits=[("self.writeReg(rd, old);", "self.writeReg(rd, rv32a.execute(op, old, rs2_val));")]),
    dict(id="C11", file=CPU, desc="fetch bound mem_size-2 -> mem_size-1", edits=[("if (self.pc > mem_size - 2) return error.PCOutOfBounds;", "if (self.pc > mem_size - 1) return error.PCOutOfBounds;")]),
    dict(id="C12", file=CPU, desc="fetch bound mem_size-4 -> mem_size-3", edits=[("if (self.pc > mem_size - 4) return error.PCOutOfBounds;", "if (self.pc > mem_size - 3) return error.PCOutOfBounds;")]),
    dict(id="C13", file=CPU, desc="fetch bound mem_size-4 -> mem_size-2 (32-bit fetch can overrun)", edits=[("if (self.pc > mem_size - 4) return error.PCOutOfBounds;", "if (self.pc > mem_size - 2) return error.PCOutOfBounds;")]),
    dict(id="C14", file=CPU, desc="fetch misaligned-PC check removed", edits=[("if (self.pc % 2 != 0) return error.MisalignedPC;", "{}")]),
    dict(id="C15", file=CPU, desc="readHalfword bound > -> >= (rejects last halfword)", edits=[("if (addr > mem_size - 2) return error.AddressOutOfBounds;\n            return std.mem.readInt(u16", "if (addr >= mem_size - 2) return error.AddressOutOfBounds;\n            return std.mem.readInt(u16")]),
    dict(id="C16", file=CPU, desc="readHalfword alignment check removed", edits=[("pub fn readHalfword(self: *const Self, addr: u32) !u16 {\n            if (addr % 2 != 0) return error.MisalignedAccess;", "pub fn readHalfword(self: *const Self, addr: u32) !u16 {\n            {}")]),
    dict(id="C17", file=CPU, desc="readWord alignment %4 -> %2 (re-targeted: private copy of the word check in readWord)", edits=[(READ_WORD, inline_word_check(2, ">", "return std.mem.readInt(u32"))]),
    dict(id="C18", file=CPU, desc="readWord bound > -> >= (rejects last word; re-targeted: private copy in readWord)", edits=[(READ_WORD, inline_word_check(4, ">=", "return std.mem.readInt(u32"))]),
    dict(id="C19", file=CPU, desc="readByte bound >= -> > (off-by-one)", edits=[("pub fn readByte(self: *const Self, addr: u32) !u8 {\n            if (addr >= mem_size)", "pub fn readByte(self: *const Self, addr: u32) !u8 {\n            if (addr > mem_size)")]),
    dict(id="C20", file=CPU, desc="writeByte bound >= -> > (off-by-one)", edits=[("pub fn writeByte(self: *Self, addr: u32, value: u8) !void {\n            if (addr >= mem_size)", "pub fn writeByte(self: *Self, addr: u32, value: u8) !void {\n            if (addr > mem_size)")]),
    dict(id="C21", file=CPU, desc="writeHalfword alignment check removed", edits=[("pub fn writeHalfword(self: *Self, addr: u32, value: u16) !void {\n            if (addr % 2 != 0) return error.MisalignedAccess;", "pub fn writeHalfword(self: *Self, addr: u32, value: u16) !void {\n            {}")]),
    dict(id="C22", file=CPU, desc="writeWord alignment %4 -> %2 (re-targeted: private copy of the word check in writeWord)", edits=[(WRITE_WORD, inline_word_check(2, ">", "std.mem.writeInt(u32"))]),
    dict(id="C23", file=CPU, desc="writeWord bound > -> >= (rejects last word; re-targeted: private copy in writeWord)", edits=[(WRITE_WORD, inline_word_check(4, ">=", "std.mem.writeInt(u32"))]),
    dict(id="C24", file=CPU, desc="cycle_count incremented before execute", edits=[(NEXT_PC, NEXT_PC + "\n            self.cycle_count +%= 1;"), ("self.cycle_count +%= 1; // INVARIANT", "// INVARIANT")]),
    dict(id="C25", file=CPU, desc="PC advanced on execute-error path (errdefer)", edits=[(NEXT_PC, NEXT_PC + "\n            errdefer self.pc = next_pc;")]),
    dict(id="C26", file=CPU, desc="cycle_count incremented on execute-error path (errdefer)", edits=[(NEXT_PC, NEXT_PC + "\n            errdefer self.cycle_count +%= 1;")]),
    dict(id="C27", file=CPU, desc="writeReg x0 protection removed (re-targeted: no regs[0] restore in writeReg)", edits=[(WRITE_REG, "self.regs[reg] = value;")]),
    dict(id="C28", file=CPU, desc="readReg(0) not forced to 0", edits=[("if (reg == 0) return 0;\n            return self.regs[reg];", "return self.regs[reg];")]),
    dict(id="C29", file=CPU, desc="x0 hardwiring removed everywhere (readReg branch, writeReg restore, step() zeroing)", edits=[("if (reg == 0) return 0;\n            return self.regs[reg];", "return self.regs[reg];"), (WRITE_REG, "self.regs[reg] = value;"), (STEP_ZERO, "const rs1_val")]),
    dict(id="C30", file=CPU, desc="inst_size always 4", edits=[("const inst_size: u32 = if (instructions.isCompressed(raw)) 2 else 4;", "const inst_size: u32 = 4;")]),
    dict(id="C31", file=CPU, desc="SC.W succeeds with any reservation (address not compared)", edits=[("if (self.reservation == addr) {", "if (self.reservation != null) {")]),
    dict(id="C32", file=CPU, desc="run(): limit check >= -> > (one extra step)", edits=[("if (self.cycle_count >= limit) return result;", "if (self.cycle_count > limit) return result;")]),
    dict(id="C33", file=CPU, desc="CSR immediate variants use rs1 register value instead of zimm", edits=[(".CSRRWI, .CSRRSI, .CSRRCI => @intCast(rs1_field),", ".CSRRWI, .CSRRSI, .CSRRCI => rs1_val,")]),
    dict(id="C34", file=CPU, desc="executeZbb src2 selection inverted (R uses imm, I uses rs2)", edits=[("if (op.format() == .R) rs2_val else imm;\n            self.writeReg(rd, zbb.execute(", "if (op.format() == .I) rs2_val else imm;\n            self.writeReg(rd, zbb.execute(")]),
    dict(id="C35", file=CPU, desc="CSR write-suppression keyed on rs1 VALUE instead of rs1 FIELD", edits=[("rd != 0, rs1_field != 0);", "rd != 0, src_val != 0);")]),

    # ---------------- zicsr.zig ----------------
    dict(id="Z01", file=CSR, desc="CSRRS/CSRRSI writes even when src field is zero", edits=[("if (src_nonzero) {\n                    try self.write(csr_addr, old | src_val);", "if (src_nonzero or true) {\n                    try self.write(csr_addr, old | src_val);")]),
    dict(id="Z02", file=CSR, desc="CSRRC/CSRRCI writes even when src field is zero", edits=[("if (src_nonzero) {\n                    try self.write(csr_addr, old & ~src_val);", "if (src_nonzero or true) {\n                    try self.write(csr_addr, old & ~src_val);")]),
    dict(id="Z03", file=CSR, desc="CSRRW/CSRRWI reads even when rd == x0", edits=[("if (rd_nonzero) {", "if (rd_nonzero or true) {")]),
    dict(id="Z04", file=CSR, desc="read-only CSR check removed from write()", edits=[("if ((addr >> 10) & 0b11 == 0b11) return error.IllegalInstruction;", "{}")]),
    dict(id="Z05", file=CSR, desc="cycleh/instreth return low word", edits=[("0xC80, 0xC82 => @truncate(cycle_count >> 32),", "0xC80, 0xC82 => @truncate(cycle_count),")]),
    dict(id="Z06", file=CSR, desc="instret (0xC02) not aliased to cycle", edits=[("0xC00, 0xC02 =>", "0xC00 =>")]),
    dict(id="Z07", file=CSR, desc="CSRRC/CSRRCI use | instead of & ~", edits=[("old & ~src_val", "old | src_val")]),
    dict(id="Z08", file=CSR, desc="CSRRS/CSRRSI use ^ instead of |", edits=[("old | src_val", "old ^ src_val")]),
    dict(id="Z09", file=CSR, desc="CSRRW returns the NEW value (write before read)", edits=[("result.rd_val = try self.read(cycle_count, csr_addr);", "try self.write(csr_addr, src_val);\n                    result.rd_val = try self.read(cycle_count, csr_addr);")]),
    dict(id="Z10", file=CSR, desc="decodeSystem maps funct3=110 to CSRRCI", edits=[("0b110 => .CSRRSI,", "0b110 => .CSRRCI,")]),

    # ---------------- rv32m.zig ----------------
    dict(id="M01", file=M, desc="MULH treats rs2 as unsigned", edits=[("const b: i64 = @as(i32, @bitCast(rs2_val));", "const b: i64 = @as(u32, rs2_val);")]),
    dict(id="M02", file=M, desc="MULHSU treats rs2 as signed", edits=[("const b: i64 = @as(u32, rs2_val);", "const b: i64 = @as(i32, @bitCast(rs2_val));")]),
    dict(id="M03", file=M, desc="MULHU sign-extends rs1", edits=[("const a: u64 = rs1_val;", "const a: u64 = @bitCast(@as(i64, @as(i32, @bitCast(rs1_val))));")]),
    dict(id="M04", file=M, desc="MULHSU treats rs1 as unsigned", edits=[(".MULHSU => blk: {\n            const a: i64 = @as(i32, @bitCast(rs1_val));", ".MULHSU => blk: {\n            const a: i64 = @as(u32, rs1_val);")]),
    dict(id="M05", file=M, desc="DIV by zero returns 0 instead of -1", edits=[("if (b == 0)\n                -1", "if (b == 0)\n                0")]),
    dict(id="M06", file=M, desc="DIV overflow returns maxInt instead of minInt", edits=[("and b == -1)\n                std.math.minInt(i32)", "and b == -1)\n                std.math.maxInt(i32)")]),
    dict(id="M07", file=M, desc="REM uses @mod instead of @rem", edits=[("@rem(a, b)", "@mod(a, b)")]),
    dict(id="M08", file=M, desc="REMU by zero returns 0 instead of rs1", edits=[("if (rs2_val == 0) rs1_val else", "if (rs2_val == 0) 0 else")]),
    dict(id="M09", file=M, desc="DIVU by zero returns 0 instead of 0xFFFFFFFF", edits=[("if (rs2_val == 0) 0xFFFFFFFF else", "if (rs2_val == 0) 0 else")]),
    dict(id="M10", file=M, desc="REM overflow (minInt % -1) returns dividend instead of 0", edits=[("and b == -1)\n                0\n", "and b == -1)\n                a\n")]),
    dict(id="M11", file=M, desc="REM by zero returns 0 instead of dividend", edits=[("if (b == 0)\n                a\n", "if (b == 0)\n                0\n")]),

    # ---------------- rv32a.zig ----------------
    dict(id="A01", file=A, desc="AMOMIN signed -> unsigned", edits=[("@bitCast(@min(@as(i32, @bitCast(old)), @as(i32, @bitCast(rs2_val))))", "@min(old, rs2_val)")]),
    dict(id="A02", file=A, desc="AMOMAX signed -> unsigned", edits=[("@bitCast(@max(@as(i32, @bitCast(old)), @as(i32, @bitCast(rs2_val))))", "@max(old, rs2_val)")]),
    dict(id="A03", file=A, desc="AMOMINU computes max", edits=[(".AMOMINU_W => @min(old, rs2_val),", ".AMOMINU_W => @max(old, rs2_val),")]),
    dict(id="A04", file=A, desc="AMOMAXU computes min", edits=[(".AMOMAXU_W => @max(old, rs2_val),", ".AMOMAXU_W => @min(old, rs2_val),")]),
    dict(id="A05", file=A, desc="AMOADD -> wrapping sub", edits=[("old +% rs2_val", "old -% rs2_val")]),
    dict(id="A06", file=A, desc="AMOXOR -> OR", edits=[("old ^ rs2_val", "old | rs2_val")]),
    dict(id="A07", file=A, desc="AMOMINU unsigned -> signed", edits=[(".AMOMINU_W => @min(old, rs2_val),", ".AMOMINU_W => @bitCast(@min(@as(i32, @bitCast(old)), @as(i32, @bitCast(rs2_val)))),")]),
    dict(id="A08", file=A, desc="AMOSWAP stores old value (no-op)", edits=[(".AMOSWAP_W => rs2_val,", ".AMOSWAP_W => old,")]),
    dict(id="A09", file=A, desc="decodeR maps AMOMAX f5 to AMOMAXU", edits=[("0b10100 => .AMOMAX_W,", "0b10100 => .AMOMAXU_W,")]),

    # ---------------- zba / zbb / zbs ----------------
    dict(id="B01", file=ZBA, desc="SH1ADD shifts by 2", edits=[(".SH1ADD => (rs1_val << 1)", ".SH1ADD => (rs1_val << 2)")]),
    dict(id="B02", file=ZBA, desc="SH2ADD operands swapped (rs2<<2 + rs1)", edits=[("(rs1_val << 2) +% rs2_val", "(rs2_val << 2) +% rs1_val")]),
    dict(id="B03", file=ZBB, desc="ROL computes ROR", edits=[("(rs1_val << shamt) | (rs1_val >> compl)", "(rs1_val >> shamt) | (rs1_val << compl)")]),
    dict(id="B04", file=ZBB, desc="RORI dispatched to ROL", edits=[(".ROL => blk: {", ".ROL, .RORI => blk: {"), (".ROR, .RORI => blk: {", ".ROR => blk: {")]),
    dict(id="B05", file=ZBB, desc="CLZ computes CTZ", edits=[(".CLZ => @clz(rs1_val),", ".CLZ => @ctz(rs1_val),")]),
    dict(id="B06", file=ZBB, desc="CPOP ignores bit 31", edits=[("@popCount(rs1_val)", "@popCount(rs1_val & 0x7FFFFFFF)")]),
    dict(id="B07", file=ZBB, desc="ORC.B byte-lane 2 test mask typo (0x00FF0000 -> 0x00FF000)", edits=[("(rs1_val & 0x00FF0000)", "(rs1_val & 0x00FF000)")]),
    dict(id="B08", file=ZBB, desc="REV8 -> bitReverse", edits=[("@byteSwap(rs1_val)", "@bitReverse(rs1_val)")]),
    dict(id="B09", file=ZBB, desc="SEXT.B zero-extends", edits=[("@bitCast(@as(i32, @as(i8, @bitCast(byte))))", "@as(u32, byte)")]),
    dict(id="B10", file=ZBB, desc="SEXT.H zero-extends", edits=[("@bitCast(@as(i32, @as(i16, @bitCast(half))))", "@as(u32, half)")]),
    dict(id="B11", file=ZBB, desc="ZEXT.H masks 0xFF", edits=[(".ZEXT_H => rs1_val & 0xFFFF,", ".ZEXT_H => rs1_val & 0xFF,")]),
    dict(id="B12", file=ZBB, desc="MIN signed -> unsigned", edits=[("@bitCast(@min(@as(i32, @bitCast(rs1_val)), @as(i32, @bitCast(src2))))", "@min(rs1_val, src2)")]),
    dict(id="B13", file=ZBB, desc="MAXU unsigned -> signed", edits=[(".MAXU => @max(rs1_val, src2),", ".MAXU => @bitCast(@max(@as(i32, @bitCast(rs1_val)), @as(i32, @bitCast(src2)))),")]),
    dict(id="B14", file=ZBB, desc="MAX signed -> unsigned", edits=[("@bitCast(@max(@as(i32, @bitCast(rs1_val)), @as(i32, @bitCast(src2))))", "@max(rs1_val, src2)")]),
    dict(id="B15", file=ZBB, desc="MINU unsigned -> signed", edits=[(".MINU => @min(rs1_val, src2),", ".MINU => @bitCast(@min(@as(i32, @bitCast(rs1_val)), @as(i32, @bitCast(src2)))),")]),
    dict(id="B16", file=ZBB, desc="ANDN negation dropped", edits=[("rs1_val & ~src2", "rs1_val & src2")]),
    dict(id="B17", file=ZBB, desc="ORN negation dropped", edits=[("rs1_val | ~src2", "rs1_val | src2")]),
    dict(id="B18", file=ZBB, desc="XNOR negation dropped", edits=[("rs1_val ^ ~src2", "rs1_val ^ src2")]),
    dict(id="B19", file=ZBB, desc="ROR/RORI complement 0-s -> 31-s", edits=[(".ROR, .RORI => blk: {\n            const shamt: u5 = @truncate(src2);\n            const compl: u5 = 0 -% shamt;", ".ROR, .RORI => blk: {\n            const shamt: u5 = @truncate(src2);\n            const compl: u5 = 31 -% shamt;")]),
    dict(id="B20", file=ZBB, desc="decodeIAlu maps rs2=4 to SEXT_H", edits=[("4 => .SEXT_B,", "4 => .SEXT_H,")]),
    dict(id="B21", file=ZBS, desc="BEXT returns the bit unshifted", edits=[("(rs1_val >> shamt) & 1", "rs1_val & (@as(u32, 1) << shamt)")]),
    dict(id="B22", file=ZBS, desc="BINV computes BSET", edits=[("rs1_val ^ (@as(u32, 1) << shamt)", "rs1_val | (@as(u32, 1) << shamt)")]),

    # ---------------- decoders: registry (the specification), bit fields, decoder ----------------
    dict(id="D01", file=REG, desc="registry SRA f7 0100000 -> 0100001", edits=[(".{ .op = .{ .i = .SRA }, .opcode7 = 0b0110011, .f3 = 0b101, .f7 = 0b0100000 }", ".{ .op = .{ .i = .SRA }, .opcode7 = 0b0110011, .f3 = 0b101, .f7 = 0b0100001 }")]),
    dict(id="D02", file=REG, desc="registry SH2ADD f3 100 -> 101", edits=[(".{ .op = .{ .zba = .SH2ADD }, .opcode7 = 0b0110011, .f3 = 0b100,", ".{ .op = .{ .zba = .SH2ADD }, .opcode7 = 0b0110011, .f3 = 0b101,")]),
    dict(id="D03", file=REG, desc="registry ZEXT_H rs2_eq 0 -> 1", edits=[(".f7 = 0b0000100, .rs2_eq = 0 }", ".f7 = 0b0000100, .rs2_eq = 1 }")]),
    dict(id="D04", file=REG, desc="registry ORC_B rs2_eq 7 -> 6", edits=[(".rs2_eq = 7 }", ".rs2_eq = 6 }")]),
    dict(id="D05", file=REG, desc="registry REV8 f7 0110100 -> 0110101", edits=[(".{ .op = .{ .zbb = .REV8 }, .opcode7 = 0b0010011, .f3 = 0b101, .f7 = 0b0110100,", ".{ .op = .{ .zbb = .REV8 }, .opcode7 = 0b0010011, .f3 = 0b101, .f7 = 0b0110101,")]),
    dict(id="D06", file=REG, desc="registry AMOMIN/AMOMINU f5 swapped", edits=[(".{ .op = .{ .a = .AMOMIN_W }, .opcode7 = 0b0101111, .f3 = 0b010, .f5 = 0b10000 }", ".{ .op = .{ .a = .AMOMIN_W }, .opcode7 = 0b0101111, .f3 = 0b010, .f5 = 0b11000 }"), (".{ .op = .{ .a = .AMOMINU_W }, .opcode7 = 0b0101111, .f3 = 0b010, .f5 = 0b11000 }", ".{ .op = .{ .a = .AMOMINU_W }, .opcode7 = 0b0101111, .f3 = 0b010, .f5 = 0b10000 }")]),
    dict(id="D07", file=REG, desc="registry ECALL/EBREAK f12 swapped", edits=[(".{ .op = .{ .i = .ECALL }, .opcode7 = 0b1110011, .f3 = 0b000, .f12 = 0x000,", ".{ .op = .{ .i = .ECALL }, .opcode7 = 0b1110011, .f3 = 0b000, .f12 = 0x001,"), (".{ .op = .{ .i = .EBREAK }, .opcode7 = 0b1110011, .f3 = 0b000, .f12 = 0x001,", ".{ .op = .{ .i = .EBREAK }, .opcode7 = 0b1110011, .f3 = 0b000, .f12 = 0x000,")]),
    dict(id="D09", file=REG, desc="registry LHU f3 101 -> 110", edits=[(".{ .op = .{ .i = .LHU }, .opcode7 = 0b0000011, .f3 = 0b101 }", ".{ .op = .{ .i = .LHU }, .opcode7 = 0b0000011, .f3 = 0b110 }")]),
    dict(id="D10", file=REG, desc="registry BLTU/BGEU f3 swapped", edits=[(".{ .op = .{ .i = .BLTU }, .opcode7 = 0b1100011, .f3 = 0b110 }", ".{ .op = .{ .i = .BLTU }, .opcode7 = 0b1100011, .f3 = 0b111 }"), (".{ .op = .{ .i = .BGEU }, .opcode7 = 0b1100011, .f3 = 0b111 }", ".{ .op = .{ .i = .BGEU }, .opcode7 = 0b1100011, .f3 = 0b110 }")]),
    dict(id="D11", file=REG, desc="registry CSRRSI/CSRRCI f3 swapped", edits=[(".{ .op = .{ .csr = .CSRRSI }, .opcode7 = 0b1110011, .f3 = 0b110 }", ".{ .op = .{ .csr = .CSRRSI }, .opcode7 = 0b1110011, .f3 = 0b111 }"), (".{ .op = .{ .csr = .CSRRCI }, .opcode7 = 0b1110011, .f3 = 0b111 }", ".{ .op = .{ .csr = .CSRRCI }, .opcode7 = 0b1110011, .f3 = 0b110 }")]),
    dict(id="D15", file=BF, desc="immB imm[11] taken from raw bit 8 instead of 7", edits=[("(raw >> 7) & 1", "(raw >> 8) & 1")]),
    dict(id="D16", file=BF, desc="immJ imm[11] taken from raw bit 21 instead of 20", edits=[("(raw >> 20) & 1", "(raw >> 21) & 1")]),
    dict(id="D17", file=BF, desc="immS drops imm[4] (mask 0x1F -> 0x0F)", edits=[("(raw >> 7) & 0x1F", "(raw >> 7) & 0x0F")]),
    dict(id="D18", file=BF, desc="immI uses logical shift (no sign extension)", edits=[("return bits >> 20;", "return @bitCast(@as(u32, @bitCast(bits)) >> 20);")]),
    dict(id="D19", file=BF, desc="immU mask typo 0xFFFFF000 -> 0x0FFFF000", edits=[("raw & 0xFFFFF000", "raw & 0x0FFFF000")]),
    dict(id="D20", file=BR, desc="decodeR: Zbb checked before RV32I", edits=[("    // RV32I base\n    if (rv32i.decodeR(f3, f7))", "    if (zbb.decodeR(f3, f7, rs2(raw))) |zop| {\n        return .{ .op = .{ .zbb = zop }, .rd = rd(raw), .rs1 = rs1(raw), .rs2 = rs2(raw), .raw = raw };\n    }\n    // RV32I base\n    if (rv32i.decodeR(f3, f7))")]),
    dict(id="D21", file=BR, desc="decodeR: M-ext funct7 guard as bit test (f7 & 1)", edits=[("if (f7 == 0b0000001) {", "if (f7 & 0b0000001 != 0) {")]),
    dict(id="D22", file=BR, desc="decodeR: RV32I checked before M-ext", edits=[("if (f7 == 0b0000001) {", "if (rv32i.decodeR(f3, f7)) |i_op0| {\n        return .{ .op = .{ .i = i_op0 }, .rd = rd(raw), .rs1 = rs1(raw), .rs2 = rs2(raw), .raw = raw };\n    }\n    if (f7 == 0b0000001) {")]),
    dict(id="D23", file=BR, desc="decodeIAlu: shamt rule only for funct3=001", edits=[("const imm_val: i32 = if (f3 == 0b001 or f3 == 0b101)", "const imm_val: i32 = if (f3 == 0b001)")]),

    # ---------------- RV32C ----------------
    dict(id="R01", file=IMM, desc="ciw_nzuimm: nzuimm[2] from bit 5 instead of 6", edits=[("((b >> 4) & 0x4) | // bit [6] → nzuimm[2]", "((b >> 3) & 0x4) | // bit [6] → nzuimm[2]")]),
    dict(id="R02", file=IMM, desc="clsw_offset: offset[2] from bit 5 instead of 6", edits=[("((b >> 4) & 0x4) | // bit [6] → offset[2]", "((b >> 3) & 0x4) | // bit [6] → offset[2]")]),
    dict(id="R03", file=IMM, desc="ci_imm: sign bit from bit 11 instead of 12", edits=[("pub fn ci_imm(half: u16) i32 {\n    const lo: u32 = (half >> 2) & 0x1F;\n    const hi: u32 = (half >> 12) & 1;", "pub fn ci_imm(half: u16) i32 {\n    const lo: u32 = (half >> 2) & 0x1F;\n    const hi: u32 = (half >> 11) & 1;")]),
    dict(id="R04", file=IMM, desc="ci_addi16sp_imm: imm[6] from bit 4 instead of 5", edits=[("((b << 1) & 0x40) | // bit[5] → imm[6]", "((b << 2) & 0x40) | // bit[5] → imm[6]")]),
    dict(id="R05", file=IMM, desc="ci_lui_imm: imm[17] placed at bit 4 (sign lost)", edits=[("const raw: u6 = @truncate((hi << 5) | lo);\n    const sign_ext: i32", "const raw: u6 = @truncate((hi << 4) | lo);\n    const sign_ext: i32")]),
    dict(id="R06", file=IMM, desc="cj_offset: offset[7] from bit 5 instead of 6", edits=[("((b << 1) & 0x80) | // bit[6] → offset[7]", "((b << 2) & 0x80) | // bit[6] → offset[7]")]),
    dict(id="R07", file=IMM, desc="cb_offset: offset[5] from bit 1 instead of 2", edits=[("((b << 3) & 0x20) | // bit[2] → offset[5]", "((b << 4) & 0x20) | // bit[2] → offset[5]")]),
    dict(id="R08", file=IMM, desc="ci_lwsp_offset: offset[7:6] from bits [4:3] instead of [3:2]", edits=[("((b << 4) & 0xC0); // bits[3:2] → offset[7:6]", "((b << 3) & 0xC0); // bits[3:2] → offset[7:6]")]),
    dict(id="R09", file=IMM, desc="css_swsp_offset: offset[7:6] from bits [9:8] instead of [8:7]", edits=[("((b >> 1) & 0xC0); // bits[8:7] → offset[7:6]", "((b >> 2) & 0xC0); // bits[8:7] → offset[7:6]")]),
    dict(id="R10", file=IMM, desc="cReg offset 8 -> 0", edits=[("return @as(u5, r) + 8;", "return @as(u5, r);")]),
    dict(id="R11", file=EXP, desc="C.ADDI4SPN nzuimm==0 reserved check removed", edits=[("if (nzu == 0) return error.IllegalInstruction;", "{}")]),
    dict(id="R12", file=EXP, desc="C.ADDI16SP imm==0 reserved check removed", edits=[("if (ci_imm_val == 0) return error.IllegalInstruction;", "{}")]),
    dict(id="R13", file=EXP, desc="C.LUI imm==0 reserved check removed", edits=[("if (lui_imm == 0) return error.IllegalInstruction;", "{}")]),
    dict(id="R14", file=EXP, desc="C.LWSP rd==0 reserved check removed", edits=[("if (rd_val == 0) return error.IllegalInstruction;", "{}")]),
    dict(id="R15", file=EXP, desc="C.JR rs1==0 reserved check removed", edits=[("if (rd_rs1 == 0) return error.IllegalInstruction;", "{}")]),
    dict(id="R16", file=EXP, desc="C.SLLI shamt[5] check removed", edits=[("const rd_val: u5 = @truncate(half >> 7);\n            const shamt = imm.ci_shamt(half);\n            if (shamt & 0x20 != 0) return error.IllegalInstruction;", "const rd_val: u5 = @truncate(half >> 7);\n            const shamt = imm.ci_shamt(half);\n            {}")]),
    dict(id="R17", file=EXP, desc="C.SRLI shamt[5] check removed", edits=[(".C_SRLI => {\n            const shamt = imm.ci_shamt(half);\n            if (shamt & 0x20 != 0) return error.IllegalInstruction;", ".C_SRLI => {\n            const shamt = imm.ci_shamt(half);\n            {}")]),
    dict(id="R18", file=EXP, desc="C.SRAI shamt[5] check removed", edits=[(".C_SRAI => {\n            const shamt = imm.ci_shamt(half);\n            if (shamt & 0x20 != 0) return error.IllegalInstruction;", ".C_SRAI => {\n            const shamt = imm.ci_shamt(half);\n            {}")]),
    dict(id="R19", file=EXP, desc="C.JALR links x0 instead of ra", edits=[(".rd = 1, // ra\n                .rs1 = rd_rs1,", ".rd = 0, // ra\n                .rs1 = rd_rs1,")]),
    dict(id="R20", file=EXP, desc="C.MV uses rs1=rd instead of x0", edits=[(".rs1 = 0,\n                .rs2 = rs2_val,", ".rs1 = rd_rs1,\n                .rs2 = rs2_val,")]),
    dict(id="R21", file=RVC, desc="C.ADD decoded as C.MV", edits=[("return .C_ADD;", "return .C_MV;")]),
    dict(id="R22", file=RVC, desc="Q1 ALU funct2b: C.XOR <-> C.OR swapped", edits=[("0b01 => .C_XOR,", "0b01 => .C_OR,"), ("0b10 => .C_OR,", "0b10 => .C_XOR,")]),
    dict(id="R23", file=RVC, desc="bit-12 RV64C guard (C.SUBW/C.ADDW space) removed", edits=[("if (funct1 != 0) return error.IllegalInstruction;", "_ = funct1;")]),
    dict(id="R24", file=EXP, desc="C.J links ra (rd=1) like C.JAL", edits=[(".op = .JAL,\n            .rd = 0,", ".op = .JAL,\n            .rd = 1,")]),
    dict(id="R25", file=EXP, desc="C.SRAI expands to SRLI", edits=[(".op = .SRAI,", ".op = .SRLI,")]),
    dict(id="R26", file=EXP, desc="C.LI uses rs1=rd instead of x0", edits=[(".rs1 = 0,\n                .imm = imm.ci_imm(half),", ".rs1 = rd_val,\n                .imm = imm.ci_imm(half),")]),
    dict(id="R27", file=EXP, desc="C.SWSP rs2 mapped through cReg", edits=[(".rs2 = @truncate(half >> 2),", ".rs2 = imm.cReg(@truncate(half >> 2)),")]),
    dict(id="R28", file=EXP, desc="C.ANDI uses unsigned shamt-style imm (no sign extension)", edits=[(".op = .ANDI,\n                .rd = rd_rs1,\n                .rs1 = rd_rs1,\n                .imm = imm.ci_imm(half),", ".op = .ANDI,\n                .rd = rd_rs1,\n                .rs1 = rd_rs1,\n                .imm = @intCast(imm.ci_shamt(half)),")]),

    # ---------------- wave 2: positive control + reservation edge cases ----------------
    dict(id="P01", file=EXEC, desc="POSITIVE CONTROL: ADD computes SUB", edits=[(".ADD => cpu.writeReg(rd, rs1_val +% rs2_val)", ".ADD => cpu.writeReg(rd, rs1_val -% rs2_val)")]),
    dict(id="C36", file=CPU, desc="invalidateReservation clears reservation on EVERY write", edits=[("if ((addr & 0xFFFFFFFC) == res_addr) {", "if (true or (addr & 0xFFFFFFFC) == res_addr) {")]),
    dict(id="C37", file=CPU, desc="SC.W skips its address check: misaligned SC.W fails softly, out-of-bounds faults only on success (re-targeted: removes the check C37 used to inject)", edits=[(SC_CHECK, "// reservation is guaranteed")]),
]

NEW = [
    # ---------------- decode cache (cpu.zig decodeCached/reset) ----------------
    dict(id="DC01", file=CPU, desc="decode cache hit on any filled slot: the fetched bits are not compared", edits=[(DECODE_CACHED, "if (slot.raw == empty_slot.raw) slot.* = try decodeFn(raw);")]),
    dict(id="DC02", file=CPU, desc="decode cache index mask is cache_entries instead of cache_entries - 1 (slot index out of range)", edits=[("(self.pc >> 1) & (cache_entries - 1)", "(self.pc >> 1) & cache_entries")]),
    dict(id="DC03", file=CPU, desc="decode cache stores raw before decoding, so a decode error leaves a stale slot that later hits", edits=[(DECODE_CACHED, "if (slot.raw != raw) {\n                slot.raw = raw;\n                slot.* = try decodeFn(raw);\n            }")]),
    dict(id="DC04", file=CPU, desc="reset() leaves the decode cache uninitialized (zeroed memory: the all-zero halfword hits a zero slot)", edits=[("self.csrs = .{};\n            @memset(&self.decode_cache, empty_slot);", "self.csrs = .{};")]),

    # ---------------- state encoding (cpu/state.zig) ----------------
    dict(id="ST01", file=STATE, desc="mscratch not encoded (written as 0)", edits=[("std.mem.writeInt(u32, buf[160..164], cpu.csrs.mscratch, .little);", "std.mem.writeInt(u32, buf[160..164], 0, .little);")]),
    dict(id="ST02", file=STATE, desc="cycle_count encoded as its low 32 bits only", edits=[("std.mem.writeInt(u64, buf[144..152], cpu.cycle_count, .little);", "std.mem.writeInt(u64, buf[144..152], cpu.cycle_count & 0xFFFFFFFF, .little);")]),
    dict(id="ST03", file=STATE, desc="pc encoded big-endian", edits=[("std.mem.writeInt(u32, buf[12..16], cpu.pc, .little);", "std.mem.writeInt(u32, buf[12..16], cpu.pc, .big);")]),
    dict(id="ST04", file=STATE, desc="reservation valid flag and address written at each other's offsets", edits=[("std.mem.writeInt(u32, buf[152..156], @intFromBool(cpu.reservation != null), .little);", "std.mem.writeInt(u32, buf[156..160], @intFromBool(cpu.reservation != null), .little);"), ("std.mem.writeInt(u32, buf[156..160], cpu.reservation orelse 0, .little);", "std.mem.writeInt(u32, buf[152..156], cpu.reservation orelse 0, .little);")]),
    dict(id="ST05", file=STATE, desc="reservation valid flag dropped (a reservation at 0 encodes like none)", edits=[("@intFromBool(cpu.reservation != null)", "0")]),
    dict(id="ST06", file=STATE, desc="last memory byte not hashed", edits=[("hasher.update(&cpu.memory);", "hasher.update(cpu.memory[0 .. cpu.memory.len - 1]);")]),
    dict(id="ST07", file=STATE, desc="regs[0] encoded as 0 instead of its stored value", edits=[("std.mem.writeInt(u32, buf[16 + 4 * i ..][0..4], r, .little);", "std.mem.writeInt(u32, buf[16 + 4 * i ..][0..4], if (i == 0) 0 else r, .little);")]),

    # ---------------- registry: the decoder's specification ----------------
    dict(id="RG01", file=REG, desc="Entry.mask: rd_eq constrains 4 bits (0x0F << 7), so ECALL/EBREAK with rd = 16 match", edits=[("if (e.rd_eq != null) m |= 0x1F << 7;", "if (e.rd_eq != null) m |= 0x0F << 7;")]),
    dict(id="RG02", file=REG, desc="lookup() gives up after the first entry of the opcode", edits=[("if (raw & e.mask() == e.match()) return e;", "return if (raw & e.mask() == e.match()) e else null;")]),
    dict(id="RG03", file=REG, desc="instruction(): shamt operand rule only for funct3=001 (SRLI/SRAI/RORI/... get immI)", edits=[("(bf.funct3(raw) == 0b001 or bf.funct3(raw) == 0b101)", "(bf.funct3(raw) == 0b001)")]),
    dict(id="RG04", file=REG, desc="instruction(): shamt operand rule keyed on the R-type opcode instead of I-ALU", edits=[("if (e.opcode7 == 0b0010011 and", "if (e.opcode7 == 0b0110011 and")]),
    dict(id="RG05", file=REG, desc="instruction(): FENCE and FENCE.I carry I-format operands", edits=[(".ECALL, .EBREAK, .FENCE, .FENCE_I => return .{ .op = op, .raw = raw },", ".ECALL, .EBREAK => return .{ .op = op, .raw = raw },")]),
    dict(id="RG06", file=REG, desc="registry SLLI entry loses its f7 constraint", edits=[(".{ .op = .{ .i = .SLLI }, .opcode7 = 0b0010011, .f3 = 0b001, .f7 = 0b0000000 },", ".{ .op = .{ .i = .SLLI }, .opcode7 = 0b0010011, .f3 = 0b001 },")]),
    dict(id="RG07", file=REG, desc="registry FENCE.I gains rd_eq = 0 (spec rejects what the decoder must accept)", edits=[(".{ .op = .{ .i = .FENCE_I }, .opcode7 = 0b0001111, .f3 = 0b001 },", ".{ .op = .{ .i = .FENCE_I }, .opcode7 = 0b0001111, .f3 = 0b001, .rd_eq = 0 },")]),

    # ---------------- checkWordAccess (shared by readWord, writeWord, SC.W) ----------------
    dict(id="CW01", file=CPU, desc="checkWordAccess alignment %4 -> %2", edits=[("if (addr % 4 != 0) return error.MisalignedAccess;", "if (addr % 2 != 0) return error.MisalignedAccess;")]),
    dict(id="CW02", file=CPU, desc="checkWordAccess bound > -> >= (rejects the last word)", edits=[("if (addr > mem_size - 4) return error.AddressOutOfBounds;", "if (addr >= mem_size - 4) return error.AddressOutOfBounds;")]),
    dict(id="CW03", file=CPU, desc="checkWordAccess checks bounds before alignment", edits=[("if (addr % 4 != 0) return error.MisalignedAccess;\n            if (addr > mem_size - 4) return error.AddressOutOfBounds;", "if (addr > mem_size - 4) return error.AddressOutOfBounds;\n            if (addr % 4 != 0) return error.MisalignedAccess;")]),
    dict(id="CW04", file=CPU, desc="checkWordAccess bound written as addr + 4 > mem_size (overflows near 0xFFFFFFFF)", edits=[("if (addr > mem_size - 4) return error.AddressOutOfBounds;", "if (addr + 4 > mem_size) return error.AddressOutOfBounds;")]),

    # ---------------- SC.W ----------------
    dict(id="SC01", file=CPU, desc="SC.W clears the reservation even when its address check faults", edits=[(SC_CHECK, "errdefer self.reservation = null;\n                    " + SC_CHECK)]),

    # ---------------- loadProgram and the reservation ----------------
    dict(id="LP01", file=CPU, desc="invalidateReservationRange: start < res + 3 (misses a load starting at the reserved word's last byte)", edits=[("start < res + 4 and", "start < res + 3 and")]),
    dict(id="LP02", file=CPU, desc="invalidateReservationRange: res + 1 < start + len (misses a load ending at the reserved word's first byte)", edits=[("res < start + len)", "res + 1 < start + len)")]),
    dict(id="LP03", file=CPU, desc="invalidateReservationRange: start <= res + 4 (clears for a load starting right after the word)", edits=[("start < res + 4 and", "start <= res + 4 and")]),
    dict(id="LP04", file=CPU, desc="invalidateReservationRange: res <= start + len (clears for a load ending right before the word)", edits=[("res < start + len)", "res <= start + len)")]),
    dict(id="LP05", file=CPU, desc="invalidateReservationRange: len != 0 guard dropped (an empty load inside the word clears it)", edits=[("if (len != 0 and start < res + 4", "if (start < res + 4")]),
    dict(id="LP06", file=CPU, desc="loadProgram does not invalidate the reservation", edits=[("self.invalidateReservationRange(off, program.len);", "{}")]),

    # ---------------- clearReservation / reset ----------------
    dict(id="CR01", file=CPU, desc="clearReservation() does nothing", edits=[("pub fn clearReservation(self: *Self) void {\n            self.reservation = null;", "pub fn clearReservation(self: *Self) void {\n            _ = self;")]),
    dict(id="RS01", file=CPU, desc="reset() keeps the reservation", edits=[("self.cycle_count = 0;\n            self.reservation = null;", "self.cycle_count = 0;")]),

    # ---------------- decoder (branch.zig): reserved encodings and guards ----------------
    dict(id="BR01", file=BR, desc="ECALL/EBREAK accept rd != 0 or rs1 != 0", edits=[("if (rd(raw) != 0 or rs1(raw) != 0) return error.IllegalInstruction;", "{}")]),
    dict(id="BR02", file=BR, desc="LR.W accepts rs2 != 0", edits=[("if (a_op == .LR_W and rs2(raw) != 0) return error.IllegalInstruction;", "{}")]),
    dict(id="BR03", file=BR, desc="the rs2 == 0 rule is applied to SC.W instead of LR.W", edits=[("if (a_op == .LR_W and rs2(raw) != 0)", "if (a_op == .SC_W and rs2(raw) != 0)")]),
    dict(id="BR04", file=BR, desc="ECALL/EBREAK funct12 mapping swapped (was D08 in the LUT)", edits=[("0x000 => .{ .op = .{ .i = .ECALL }, .raw = raw },", "0x000 => .{ .op = .{ .i = .EBREAK }, .raw = raw },"), ("0x001 => .{ .op = .{ .i = .EBREAK }, .raw = raw },", "0x001 => .{ .op = .{ .i = .ECALL }, .raw = raw },")]),
    dict(id="BR05", file=BR, desc="FENCE.I decoded as FENCE (was D12 in the LUT)", edits=[("0b001 => .{ .op = .{ .i = .FENCE_I }, .raw = raw },", "0b001 => .{ .op = .{ .i = .FENCE }, .raw = raw },")]),
    dict(id="BR06", file=BR, desc="JALR funct3 == 000 guard removed (was D25 in the LUT)", edits=[("if (funct3(raw) != 0b000) return error.IllegalInstruction;\n    return .{ .op = .{ .i = .JALR }", "return .{ .op = .{ .i = .JALR }")]),
    dict(id="BR07", file=BR, desc="atomic funct3 == 010 guard removed (was D24 in the LUT)", edits=[("if (funct3(raw) != 0b010) return error.IllegalInstruction;\n    const a_op", "const a_op")]),

    # ---------------- x0: regs[0] zeroing in step() ----------------
    dict(id="X01", file=CPU, desc="step() does not zero regs[0] before reading operands", edits=[(STEP_ZERO, "const rs1_val")]),
    dict(id="X02", file=CPU, desc="neither step() nor writeReg() zero regs[0] (readReg's branch kept)", edits=[(WRITE_REG, "self.regs[reg] = value;"), (STEP_ZERO, "const rs1_val")]),
    dict(id="X03", file=CPU, desc="step() zeroes regs[0] after reading the operands", edits=[("self.regs[0] = 0;\n            const rs1_val = self.regs[inst.rs1];\n            const rs2_val = self.regs[inst.rs2];", "const rs1_val = self.regs[inst.rs1];\n            const rs2_val = self.regs[inst.rs2];\n            self.regs[0] = 0;")]),

    # ---------------- CLI (main.zig): exit statuses and output failures ----------------
    dict(id="MN01", file=MAIN, desc="EBREAK stop maps to the cycle-limit exit status", edits=[(".ebreak, .ecall => .ok,", ".ecall => .ok,\n                .ebreak => .cycle_limit,")]),
    dict(id="MN02", file=MAIN, desc="cycle-limit stop maps to exit status 0", edits=[(".cycle_limit => .cycle_limit,", ".cycle_limit => .ok,")]),
    dict(id="MN03", file=MAIN, desc="a VM fault exits with the usage/I-O status", edits=[("break :blk .vm_fault;", "break :blk .usage_or_io;")]),
    dict(id="MN04", file=MAIN, desc="a failed final stdout flush is ignored", edits=[("cli.stdout.flush() catch return cli.outputFailed();", "cli.stdout.flush() catch {};")]),
    dict(id="MN05", file=MAIN, desc="WriteFailed from command() reported as a generic error", edits=[("            error.WriteFailed => return cli.outputFailed(),\n", "")]),

    # ---------------- host API (describeFault, runFor, stop_pc) ----------------
    dict(id="HA01", file=CPU, desc="runFor wraps the limit instead of saturating", edits=[("return self.run(self.cycle_count +| steps);", "return self.run(self.cycle_count +% steps);")]),
    dict(id="HA02", file=CPU, desc="stop_pc recorded only for ECALL", edits=[("if (result != .@\"continue\") self.stop_pc = self.pc;", "if (result == .ecall) self.stop_pc = self.pc;")]),
    dict(id="HA03", file=CPU, desc="describeFault: load/store address ignores the immediate", edits=[(".LB, .LH, .LW, .LBU, .LHU, .SB, .SH, .SW => fault.addr = rs1_val +% inst.immUnsigned(),", ".LB, .LH, .LW, .LBU, .LHU, .SB, .SH, .SW => fault.addr = rs1_val,")]),
    dict(id="HA04", file=CPU, desc="describeFault: no address for AMO/LR/SC faults", edits=[(".a => fault.addr = rs1_val,\n", "")]),
    dict(id="HA05", file=MAIN, desc="a report section is printed without flushing stdout first", edits=[("        try self.cli.stdout.flush();\n        if (self.started)", "        if (self.started)")]),

    # ---------------- host calls (hostcall.zig) ----------------
    dict(id="HC01", file=HC, desc="exit_group is not a host call", edits=[(".exit, .exit_group => return .{ .exit = a0 },", ".exit => return .{ .exit = a0 },\n        .exit_group => return .{ .unknown = number },")]),
    dict(id="HC02", file=HC, desc="write to fd 2 goes to stdout", edits=[("2 => env.stderr,", "2 => env.stdout,")]),
    dict(id="HC03", file=HC, desc="write returns 0 instead of the length", edits=[("return setResult(vm, a2);", "return setResult(vm, 0);")]),
    dict(id="HC04", file=HC, desc="guestBytes rejects a buffer that ends at the top of memory", edits=[("start > vm.memory.len - n", "start >= vm.memory.len - n")]),
    dict(id="HC05", file=HC, desc="read accepts any fd", edits=[("if (a0 != 0) return setResult(vm, ebadf);\n", "")]),
    dict(id="HC06", file=HC, desc="read does not advance the input position", edits=[("env.input_pos += n;\n", "")]),
    dict(id="HC07", file=HC, desc="read ignores the count and copies all remaining input", edits=[("@min(a2, env.input.len - env.input_pos)", "env.input.len - env.input_pos")]),
    dict(id="HC08", file=HC, desc="read writes guest memory directly, keeping the LR reservation", edits=[("vm.loadProgram(env.input[env.input_pos..][0..n], a1) catch unreachable; // range checked above", "@memcpy(vm.memory[a1..][0..n], env.input[env.input_pos..][0..n]);")]),
    dict(id="HC09", file=HC, desc="read does not check the buffer", edits=[("if (guestBytes(vm, a1, a2) == null) return setResult(vm, efault);\n", "")]),
    dict(id="HC10", file=HC, desc="an unknown call resumes with -EBADF instead of stopping", edits=[("_ => return .{ .unknown = number },", "_ => return setResult(vm, ebadf),")]),
    dict(id="HC11", file=HC, desc="read checks the buffer against the remaining input instead of the count", edits=[("if (guestBytes(vm, a1, a2) == null)", "if (guestBytes(vm, a1, @intCast(env.input.len - env.input_pos)) == null)")]),

    # ---------------- ELF loading (loader.zig) ----------------
    dict(id="LD01", file=LD, desc="ELF class not checked", edits=[("if (image[4] != ELFCLASS32 or image[5] != ELFDATA2LSB", "if (image[5] != ELFDATA2LSB")]),
    dict(id="LD02", file=LD, desc="ELF byte order not checked", edits=[("image[4] != ELFCLASS32 or image[5] != ELFDATA2LSB or ", "image[4] != ELFCLASS32 or ")]),
    dict(id="LD03", file=LD, desc="odd entry point accepted", edits=[("if (entry % 2 != 0) return error.InvalidElf;\n", "")]),
    dict(id="LD04", file=LD, desc="program header entries smaller than 32 bytes accepted", edits=[("if (phnum != 0 and phentsize < program_header_len) return error.InvalidElf;\n", "")]),
    dict(id="LD05", file=LD, desc="a program header table that ends at the end of the file is rejected", edits=[("if (phoff + phentsize * phnum > image.len)", "if (phoff + phentsize * phnum >= image.len)")]),
    dict(id="LD06", file=LD, desc="segment file range not checked", edits=[("        if (@as(u64, s.offset) + s.filesz > image.len) return error.InvalidElf;\n", "")]),
    dict(id="LD07", file=LD, desc="p_filesz > p_memsz accepted", edits=[("        if (s.filesz > s.memsz) return error.InvalidElf;\n", "")]),
    dict(id="LD08", file=LD, desc="a segment that ends at the top of memory is rejected", edits=[("if (@as(u64, s.vaddr) + s.memsz > mem_size)", "if (@as(u64, s.vaddr) + s.memsz >= mem_size)")]),
    dict(id="LD09", file=LD, desc="memory bounds checked while writing, so a rejected image is partly loaded", edits=[("    var check = elf.segments;\n    while (check.next()) |s| {\n        if (@as(u64, s.vaddr) + s.memsz > mem_size) return error.AddressOutOfBounds;\n    }\n", ""), ("vm.loadProgram(image[s.offset..][0..s.filesz], s.vaddr) catch unreachable; // validated above", "try vm.loadProgram(image[s.offset..][0..s.filesz], s.vaddr);\n        if (@as(u64, s.vaddr) + s.memsz > mem_size) return error.AddressOutOfBounds;")]),
    dict(id="LD10", file=LD, desc="segments of every type are loaded, not only PT_LOAD", edits=[("if (u32At(image, ph) != PT_LOAD) return null;\n", "")]),
    dict(id="LD11", file=LD, desc=".bss not zero-filled", edits=[("@memset(vm.memory[bss_start..bss_end], 0);", "{}")]),
    dict(id="LD12", file=LD, desc="zero-filling .bss keeps the LR reservation", edits=[("vm.clearReservation(); // a direct memory write", "{}")]),
    dict(id="LD13", file=LD, desc="ELF type not checked (ET_DYN accepted)", edits=[("u16At(image, 16) != ET_EXEC or ", "")]),

    # ---------------- snapshots (state.zig, restoreSnapshot) ----------------
    dict(id="SN01", file=STATE, desc="snapshot magic not checked", edits=[("if (!std.mem.eql(u8, hdr[0..4], &magic)) return error.InvalidSnapshot;\n", "")]),
    dict(id="SN02", file=STATE, desc="snapshot version not checked", edits=[("if (readU32(&hdr, 4) != version) return error.InvalidSnapshot;\n", "")]),
    dict(id="SN03", file=STATE, desc="snapshot memory size not checked", edits=[("if (readU32(&hdr, 8) != Cpu.mem_size) return error.InvalidSnapshot;\n", "")]),
    dict(id="SN04", file=STATE, desc="a snapshot with regs[0] != 0 accepted", edits=[("if (readU32(&hdr, 16) != 0) return error.InvalidSnapshot; // regs[0]\n", "")]),
    dict(id="SN05", file=STATE, desc="a misaligned reservation accepted", edits=[("1 => if (res_addr % 4 != 0 or res_addr > Cpu.mem_size - 4)", "1 => if (res_addr > Cpu.mem_size - 4)")]),
    dict(id="SN06", file=STATE, desc="a reservation on the last word rejected", edits=[("res_addr > Cpu.mem_size - 4", "res_addr >= Cpu.mem_size - 4")]),
    dict(id="SN07", file=STATE, desc="no reservation but a nonzero reservation address accepted", edits=[("0 => if (res_addr != 0) return error.InvalidSnapshot,", "0 => {},")]),
    dict(id="SN08", file=STATE, desc="a reservation flag other than 0 or 1 accepted (as none)", edits=[("else => return error.InvalidSnapshot,\n    }", "else => {},\n    }")]),
    dict(id="SN09", file=STATE, desc="mscratch not restored", edits=[("cpu.csrs = .{ .mscratch = readU32(&hdr, 160) };", "cpu.csrs = .{};")]),
    dict(id="SN10", file=STATE, desc="only the low 32 bits of cycle_count restored", edits=[("cpu.cycle_count = std.mem.readInt(u64, hdr[144..152], .little);", "cpu.cycle_count = std.mem.readInt(u32, hdr[144..148], .little);")]),
    dict(id="SN11", file=STATE, desc="pc restored before the header is validated", edits=[("    try r.readSliceAll(&hdr);\n", "    try r.readSliceAll(&hdr);\n    cpu.pc = readU32(&hdr, 12);\n"), ("    cpu.pc = readU32(&hdr, 12);\n    for (&cpu.regs", "    for (&cpu.regs")]),
    dict(id="SN12", file=CPU, desc="restoreSnapshot keeps stop_pc", edits=[("try state.restoreSnapshot(self, r);\n            @memset(&self.decode_cache, empty_slot);\n            self.stop_pc = 0;", "try state.restoreSnapshot(self, r);\n            @memset(&self.decode_cache, empty_slot);")]),
    dict(id="SN13", file=STATE, desc="the reservation's valid flag is not encoded (a reservation is lost on restore)", edits=[("std.mem.writeInt(u32, buf[152..156], @intFromBool(cpu.reservation != null), .little);", "std.mem.writeInt(u32, buf[152..156], 0, .little);")]),

    # ---------------- CLI loading and exit (main.zig, main/load.zig) ----------------
    dict(id="CL01", file=MAIN, desc="initial sp 16 bytes below the top of memory", edits=[("pub const initial_sp: u32 = det.Cpu.mem_size & ~@as(u32, 15);", "pub const initial_sp: u32 = (det.Cpu.mem_size & ~@as(u32, 15)) -% 16;")]),
    dict(id="CL02", file=ARGS, desc="an odd --load-addr accepted", edits=[("if (addr % 2 != 0 or addr >= mem_size)", "if (addr >= mem_size)")]),
    dict(id="CL03", file=LOADC, desc="a flat binary starts at 0 instead of its load address", edits=[("        .entry = addr,\n", "        .entry = 0,\n")]),
    dict(id="CL04", file=MAIN, desc="--input ignored", edits=[(".{ .input = input, .stdout = cli.stdout", ".{ .input = &.{}, .stdout = cli.stdout")]),
    dict(id="CL05", file=MAIN, desc="exit status saturates at 255 instead of keeping the low 8 bits", edits=[(".exit => |s| @fromBackingInt(@as(u8, @truncate(s))),", ".exit => |s| @fromBackingInt(@as(u8, @intCast(@min(s, 255)))),")]),
    dict(id="CL06", file=MAIN, desc="a fault skips --dump-memory and --digest", edits=[("        if (config.dump) |d| {", "        if (status == .vm_fault) return status;\n        if (config.dump) |d| {")]),
    dict(id="CL07", file=LOADC, desc="ELF detection checks the magic one byte late, so ELF files load as flat binaries", edits=[("if (det.loader.isElf(magic[0..magic_len])) {", "if (det.loader.isElf(magic[1..magic_len])) {")]),
    dict(id="CL08", file=LOADC, desc="--load-addr accepted with an ELF file (and ignored)", edits=[("        if (load_addr != null) return report.userError(diag, \"--load-addr is for flat binaries", "        if (false) return report.userError(diag, \"--load-addr is for flat binaries")]),
    dict(id="CL09", file=LOADC, desc="an empty file is run instead of rejected", edits=[("    if (stat.size == 0) return report.userError(diag, \"'{s}' is empty\", .{path});\n", "")]),

    # ---------------- CLI arguments (main/args.zig) ----------------
    dict(id="AR01", file=ARGS, desc="'--' does not end the options", edits=[("            options_ended = true;\n", "            options_ended = options_ended;\n")]),
    dict(id="AR02", file=ARGS, desc="the value after '=' is dropped (the next argument is taken instead)", edits=[("            inline_value = cut[1];", "            inline_value = null;")]),
    dict(id="AR03", file=ARGS, desc="the --help/--version scan does not stop at '--'", edits=[("        if (std.mem.eql(u8, arg, \"--\")) break;\n", "")]),
    dict(id="AR04", file=ARGS, desc="a second program argument replaces the first", edits=[("            if (program) |first| return fail(diag, \"unexpected argument '{s}' after the program '{s}' (programs take no arguments)\", .{ arg, first });\n", "")]),
    dict(id="AR05", file=ARGS, desc="a negative number is not reported as negative", edits=[("    if (std.mem.startsWith(u8, text, \"-\")) return fail(diag, \"{s} '{s}' is negative\", .{ option, text });\n", "")]),
    dict(id="AR06", file=ARGS, desc="a --dump-range that ends at the top of memory is rejected", edits=[("if (@as(u64, range.start) + range.len > mem_size)", "if (@as(u64, range.start) + range.len >= mem_size)")]),
    dict(id="AR07", file=ARGS, desc="the --dump-range end wraps around 2^32", edits=[("if (@as(u64, range.start) + range.len > mem_size)", "if (range.start +% range.len > mem_size)")]),
    dict(id="AR08", file=ARGS, desc="--disassemble accepts the options that only apply to a run", edits=[("            if (o[1]) return fail(diag, \"{s} does not apply to --disassemble", "            if (false and o[1]) return fail(diag, \"{s} does not apply to --disassemble")]),
    dict(id="AR09", file=ARGS, desc="--load-addr accepted with --demo", edits=[("        if (config.load_addr != null) return fail(diag, \"--load-addr does not apply to --demo\", .{});\n", "")]),
    dict(id="AR10", file=ARGS, desc="--input - names a file '-' instead of stdin", edits=[(".input => config.input = if (std.mem.eql(u8, value.?, \"-\")) .stdin else .{ .file = value.? },", ".input => config.input = .{ .file = value.? },")]),
    dict(id="AR11", file=ARGS, desc="--dump-range resets the format to hexdump", edits=[("                var d = config.dump orelse Dump{};\n                d.range", "                var d: Dump = .{};\n                d.range")]),

    # ---------------- CLI streams, report, trace and listing ----------------
    dict(id="SO01", file=MAIN, desc="a guest write to stderr does not flush stdout first", edits=[("                2 => try cli.stdout.flush(),", "                2 => {},")]),
    dict(id="SO02", file=MAIN, desc="a guest write to stdout does not flush stderr first", edits=[("                1 => try cli.stderr.flush(),", "                1 => {},")]),
    dict(id="SO03", file=MAIN, desc="the preamble is not flushed before the program runs", edits=[("            try cli.stderr.flush(); // before the program's output\n", "")]),
    dict(id="SO04", file=MAIN, desc="-q does not drop the result report", edits=[("        const status: ExitStatus = if (cli.execute(vm, config, &env)) |stop| blk: {\n            if (!config.quiet) {", "        const status: ExitStatus = if (cli.execute(vm, config, &env)) |stop| blk: {\n            if (true) {")]),
    dict(id="RP01", file=REPORT, desc="the register table leaves out x31", edits=[("    for (1..32) |i| {", "    for (1..31) |i| {")]),
    dict(id="RP02", file=REPORT, desc="an EBREAK stop shows pc (past it) instead of its own address", edits=[("after {f}\\n\", .{ vm.stop_pc, n }),\n        .ecall", "after {f}\\n\", .{ vm.pc, n }),\n        .ecall")]),
    dict(id="RP03", file=REPORT, desc="an exit status is printed unsigned", edits=[(".{ @as(i32, @bitCast(status)), n }", ".{ status, n }")]),
    dict(id="RP04", file=REPORT, desc="no memory hint for a data address outside memory", edits=[("if (err == error.AddressOutOfBounds) try w.print", "if (false) try w.print")]),
    dict(id="RP05", file=REPORT, desc="the trace shows a byte store with 8 digits", edits=[(".SB => try w.print(\"0x{X:0>2}\\n\", .{@as(u8, @truncate(val))}),", ".SB => try w.print(\"0x{X:0>8}\\n\", .{val}),")]),
    dict(id="TR01", file=MAIN, desc="--trace runs one instruction past the cycle limit", edits=[("                if (vm.cycle_count >= limit) return .@\"continue\";\n            }\n            const cycle", "                if (vm.cycle_count > limit) return .@\"continue\";\n            }\n            const cycle")]),
    dict(id="TR02", file=MAIN, desc="--trace fetches the bits after step(), so a self-overwriting instruction shows its new bits", edits=[("            const raw = try vm.fetch(); // before step(): the instruction may overwrite itself\n            const result = try vm.step();", "            const result = try vm.step();\n            const raw = vm.memory[pc] | @as(u32, vm.memory[pc + 1]) << 8 | @as(u32, vm.memory[pc + 2]) << 16 | @as(u32, vm.memory[pc + 3]) << 24;")]),
    dict(id="DS01", file=LOADC, desc="--disassemble lists every ELF segment, not only the executable ones", edits=[("if (s.flags & det.loader.PF_X != 0) try code.append", "if (s.flags != 0xFFFF_FFFF) try code.append")]),
    dict(id="DS02", file=DISASM, desc="the listing steps 4 bytes over a 16-bit instruction", edits=[("addr += if (det.instructions.isCompressed(raw)) 2 else 4;", "addr += 4;")]),
    dict(id="DS03", file=DISASM, desc="a branch target is relative to the next instruction, not to its own address", edits=[("return w.print(\"0x{X:0>8}\", .{pc +% @as(u32, @bitCast(self.offset))});", "return w.print(\"0x{X:0>8}\", .{pc +% 4 +% @as(u32, @bitCast(self.offset))});")]),
    dict(id="DM01", file=DUMP, desc="hexdump addresses ignore the base address", edits=[("try w.print(\"{X:0>8}  \", .{base + offset});", "try w.print(\"{X:0>8}  \", .{offset});")]),
    dict(id="DM02", file=MAIN, desc="--dump-range dumps all of memory", edits=[("const range = d.range orelse args.Range{ .start = 0, .len = det.Cpu.mem_size };", "const range = args.Range{ .start = 0, .len = det.Cpu.mem_size };")]),
    dict(id="UN01", file=UNITS, desc="0 is counted as singular (\"0 cycle\")", edits=[("if (self.n == 1) \"\" else \"s\"", "if (self.n <= 1) \"\" else \"s\"")]),
    dict(id="LD14", file=LD, desc="segments() returns an iterator that the checks already ran to the end", edits=[("return .{ .entry = entry, .segments = all };", "return .{ .entry = entry, .segments = it };")]),
]

MUTANTS = PORTED + NEW

# Survivors that change no observable behaviour, with the reason. The report leaves
# them out of the score. Filled in from the analysis of a run; an ID listed here that
# a later run kills is reported as a contradiction.
EQUIVALENT = {
    "I06": "the shift amount is @truncate'd to u5, which drops bit 5 whether the mask is 0x1F or 0x3F",
    "I15": "rs1 was read before execute, so writing rd early cannot change the JALR target; rd gets the same value again",
    "C06": "the successful SC.W's writeWord() already cleared the reservation, so the skipped `reservation = null` was a no-op",
    "C09": "writeWord() repeats the checkWordAccess() that readWord() just passed, so it cannot fault after the early rd write; rs2 was read before execute",
    "C11": "fetch() rejects an odd pc first and mem_size is a multiple of 4, so pc > mem_size - 2 and pc > mem_size - 1 reject the same even pcs",
    "C12": "pc is even and mem_size - 4 is even, so pc > mem_size - 4 and pc > mem_size - 3 reject the same pcs",
    "Z03": "CSR reads have no side effects, and every CSR whose read fails also fails the write that follows (only mscratch is writable) with the same IllegalInstruction",
    "Z04": "write()'s switch rejects every CSR but mscratch anyway; the read-only check only guards writable CSRs added later",
    "D20": "no two registry entries overlap (registry_test), so the order in which decodeR asks the extensions cannot change its result",
    "D22": "no two registry entries overlap (registry_test), so the order in which decodeR asks the extensions cannot change its result",
    "SO03": "every guest write to stdout flushes stderr first, and everything else on stderr follows the preamble in the same buffer, so the order is the same; the flush only shows the line before a long run starts, which no test can see",
}
