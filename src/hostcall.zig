//! The host-call ABI: the standard way for a host to handle the guest ECALL that
//! stopped run() with .ecall (docs/design/host-calls.md). The VM core only stops;
//! this module performs read/write/exit using the Linux RISC-V syscall numbers.
//!
//! Every effect on the guest depends only on the VM state and on `Env.input`, which is
//! fixed before the run: there is no time, randomness or other host state.

const std = @import("std");

/// Call numbers, in a7 (Linux RISC-V numbering).
pub const Call = enum(u32) {
    read = 63,
    write = 64,
    exit = 93,
    exit_group = 94,
    _,
};

/// Error results, in a0 (negative Linux errno values).
pub const ebadf: u32 = @bitCast(@as(i32, -9));
pub const efault: u32 = @bitCast(@as(i32, -14));

/// The host side of a run.
pub const Env = struct {
    /// What `read` on fd 0 returns, fixed before the run.
    input: []const u8 = &.{},
    /// How much of `input` has been read so far.
    input_pos: usize = 0,
    /// Where `write` on fd 1 and fd 2 goes.
    stdout: *std.Io.Writer,
    stderr: *std.Io.Writer,
};

pub const Outcome = union(enum) {
    /// The call was performed (a0 holds its result): continue with run().
    resumed,
    /// The guest called exit or exit_group with this status (a0).
    exit: u32,
    /// a7 holds no host call; nothing was changed. The host decides what to do (the
    /// CLI stops, as for any ECALL; an embedder may write -ENOSYS to a0 and resume).
    unknown: u32,
};

/// Handle the ECALL that just stopped `vm` (any CpuType). Fails only if writing the
/// guest's output to `env.stdout`/`env.stderr` fails — a host problem, not a result
/// the guest sees.
pub fn handle(vm: anytype, env: *Env) std.Io.Writer.Error!Outcome {
    const number = vm.readReg(17); // a7
    const a0 = vm.readReg(10);
    const a1 = vm.readReg(11);
    const a2 = vm.readReg(12);
    switch (@as(Call, @fromBackingInt(number))) {
        .exit, .exit_group => return .{ .exit = a0 },
        .write => {
            const out = switch (a0) {
                1 => env.stdout,
                2 => env.stderr,
                else => return setResult(vm, ebadf),
            };
            const bytes = guestBytes(vm, a1, a2) orelse return setResult(vm, efault);
            try out.writeAll(bytes);
            return setResult(vm, a2);
        },
        .read => {
            if (a0 != 0) return setResult(vm, ebadf);
            if (guestBytes(vm, a1, a2) == null) return setResult(vm, efault);
            const n: u32 = @intCast(@min(a2, env.input.len - env.input_pos));
            // loadProgram drops an LR reservation on any word it overwrites.
            vm.loadProgram(env.input[env.input_pos..][0..n], a1) catch unreachable; // range checked above
            env.input_pos += n;
            return setResult(vm, n);
        },
        _ => return .{ .unknown = number },
    }
}

fn setResult(vm: anytype, a0: u32) Outcome {
    vm.writeReg(10, a0);
    return .resumed;
}

/// The guest bytes [addr, addr + len), or null if they do not lie inside memory.
fn guestBytes(vm: anytype, addr: u32, len: u32) ?[]const u8 {
    const start: usize = addr;
    const n: usize = len;
    if (n > vm.memory.len or start > vm.memory.len - n) return null;
    return vm.memory[start..][0..n];
}

test {
    _ = @import("hostcall_test.zig");
}
