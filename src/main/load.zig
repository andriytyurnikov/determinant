//! Putting the program into the VM: an ELF32 executable at its segments, a flat binary
//! at --load-addr, or the built-in demo (docs/design/program-loading.md).

const std = @import("std");
const Io = std.Io;
const det = @import("determinant");
const args = @import("args.zig");
const report = @import("report.zig");
const units = @import("units.zig");

/// Built-in 5-instruction RV32I demo program:
///   ADDI x1, x0, 100    — x1 = 100
///   ADDI x2, x0, 10     — x2 = 10
///   ADD  x3, x1, x2     — x3 = x1 + x2 = 110
///   SW   x3, 0(x1)      — mem[100] = 110
///   ECALL                — stop (a7 = 0 is not a host call)
pub const demo_program = [_]u8{
    0x93, 0x00, 0x40, 0x06, // ADDI x1, x0, 100
    0x13, 0x01, 0xA0, 0x00, // ADDI x2, x0, 10
    0xB3, 0x81, 0x20, 0x00, // ADD  x3, x1, x2
    0x23, 0xA0, 0x30, 0x00, // SW   x3, 0(x1)
    0x73, 0x00, 0x00, 0x00, // ECALL
};

/// Address the demo program stores its result to.
pub const demo_store_addr: u32 = 100;

/// Smallest VM memory in which the demo runs to completion (its store must fit).
pub const demo_min_memory: u32 = demo_store_addr + 4;

/// Largest ELF file accepted (flat binaries are limited by the VM memory instead).
const max_elf = 1 << 30;

/// A program in the VM.
pub const Loaded = struct {
    source: Source,
    entry: u32,
    /// Where the code is, for --disassemble: the whole flat binary, or the ELF file's
    /// executable segments. Owned.
    code: []const args.Range,

    pub const Source = union(enum) {
        demo,
        flat: struct { path: []const u8, size: u32 },
        elf: []const u8,
    };

    pub fn deinit(self: Loaded, gpa: std.mem.Allocator) void {
        gpa.free(self.code);
    }

    /// "hello.bin (42 bytes at 0x00000000)", for the report.
    pub fn format(self: Loaded, w: *Io.Writer) Io.Writer.Error!void {
        switch (self.source) {
            .demo => try w.print("the demo ({f} at 0x{X:0>8})", .{ units.count(demo_program.len, "byte"), self.entry }),
            .flat => |f| try w.print("{s} ({f} at 0x{X:0>8})", .{ f.path, units.count(f.size, "byte"), self.entry }),
            .elf => |path| try w.print("{s} (ELF executable, entry 0x{X:0>8})", .{ path, self.entry }),
        }
    }
};

/// Load the program `config` names into `vm`, a reset VM (a CpuType or a
/// RuntimeCpuType). Usage and I/O errors are reported on `diag` and return
/// error.UserError.
pub fn load(io: Io, gpa: std.mem.Allocator, diag: *Io.Writer, vm: anytype, config: args.Config) !Loaded {
    switch (config.program) {
        .demo => {
            vm.loadProgram(&demo_program, 0) catch return report.userError(
                diag,
                "the demo program needs {d} bytes of VM memory, and there are {f}{s}",
                .{ demo_program.len, units.MemSize{ .bytes = vm.memSize() }, report.memory_hint },
            );
            return .{ .source = .demo, .entry = 0, .code = try gpa.dupe(args.Range, &.{.{ .start = 0, .len = demo_program.len }}) };
        },
        .file => |path| return loadFile(io, gpa, diag, vm, path, config.load_addr),
    }
}

fn loadFile(io: Io, gpa: std.mem.Allocator, diag: *Io.Writer, vm: anytype, path: []const u8, load_addr: ?u32) !Loaded {
    const mem_size: units.MemSize = .{ .bytes = vm.memSize() };
    var file = Io.Dir.cwd().openFile(io, path, .{}) catch |err|
        return report.userError(diag, "cannot open '{s}': {s}", .{ path, report.ioText(err) });
    defer file.close(io);
    const stat = file.stat(io) catch |err|
        return report.userError(diag, "cannot read '{s}': {s}", .{ path, report.ioText(err) });

    var magic: [4]u8 = undefined;
    const magic_len = file.readPositionalAll(io, &magic, 0) catch |err|
        return report.userError(diag, "cannot read '{s}': {s}", .{ path, report.ioText(err) });
    if (stat.size == 0) return report.userError(diag, "'{s}' is empty", .{path});

    if (det.loader.isElf(magic[0..magic_len])) {
        if (load_addr != null) return report.userError(diag, "--load-addr is for flat binaries, and '{s}' is an ELF executable, which says where it goes", .{path});
        if (stat.size > max_elf) return report.userError(diag, "'{s}' is too large for an ELF executable ({d} bytes)", .{ path, stat.size });
        const image = try gpa.alloc(u8, @intCast(stat.size));
        defer gpa.free(image);
        try readExactly(io, diag, file, path, image);
        const entry = det.loader.loadElf(vm, image) catch |err| switch (err) {
            error.InvalidElf => return report.userError(diag, "'{s}' is not a RISC-V ELF32 little-endian executable", .{path}),
            error.AddressOutOfBounds => return report.userError(diag, "'{s}' has a segment that is not inside the {f} of VM memory{s}", .{ path, mem_size, report.memory_hint }),
        };

        var code: std.ArrayList(args.Range) = .empty;
        errdefer code.deinit(gpa);
        var segments = det.loader.segments(image) catch unreachable; // loadElf accepted it
        while (segments.next()) |s| {
            if (s.flags & det.loader.PF_X != 0) try code.append(gpa, .{ .start = s.vaddr, .len = s.filesz });
        }
        return .{ .source = .{ .elf = path }, .entry = entry, .code = try code.toOwnedSlice(gpa) };
    }

    const addr = load_addr orelse 0;
    const room = vm.memSize() - addr;
    if (stat.size > room) return report.userError(
        diag,
        "'{s}' is too large: {d} bytes, and {d} fit at 0x{X:0>8} in the {f} of VM memory{s}",
        .{ path, stat.size, room, addr, mem_size, report.memory_hint },
    );
    const size: u32 = @intCast(stat.size);
    // Read directly into VM memory instead of going through loadProgram(), to avoid an
    // intermediate buffer as large as the file. Direct memory writes must drop the LR
    // reservation.
    try readExactly(io, diag, file, path, vm.memory[addr..][0..size]);
    vm.clearReservation();
    return .{
        .source = .{ .flat = .{ .path = path, .size = size } },
        .entry = addr,
        .code = try gpa.dupe(args.Range, &.{.{ .start = addr, .len = size }}),
    };
}

/// Read exactly buf.len bytes from the start of the file, or report the problem.
fn readExactly(io: Io, diag: *Io.Writer, file: Io.File, path: []const u8, buf: []u8) !void {
    const n = file.readPositionalAll(io, buf, 0) catch |err|
        return report.userError(diag, "cannot read '{s}': {s}", .{ path, report.ioText(err) });
    if (n != buf.len) return report.userError(diag, "cannot read '{s}': it ended after {d} of its {d} bytes", .{ path, n, buf.len });
}
