const std = @import("std");
const cpu = @import("cpu.zig");
const Cpu = cpu.Cpu;
const MEMORY_SIZE = cpu.MEMORY_SIZE;

pub const SyscallResult = union(enum) {
    continue_,
    exit: u32,
};

pub const Syscall = enum(u32) {
    write = 64,
    exit = 93,
    _,
};

/// Handle a single ECALL using the Linux RISC-V syscall convention.
/// Syscall number in a7 (x17), args in a0-a2 (x10-x12), return in a0 (x10).
pub fn handleSyscall(vm: *Cpu, writer: anytype) !SyscallResult {
    const syscall_num = vm.readReg(17); // a7
    const a0 = vm.readReg(10);
    const a1 = vm.readReg(11);
    const a2 = vm.readReg(12);

    const syscall: Syscall = @enumFromInt(syscall_num);
    switch (syscall) {
        .write => {
            const fd = a0;
            const buf_ptr = a1;
            const len = a2;

            // Only fd=1 (stdout) supported
            if (fd != 1) {
                // -EBADF = -9, as u32 two's complement
                vm.writeReg(10, @bitCast(@as(i32, -9)));
                return .continue_;
            }

            // Validate buffer bounds
            if (buf_ptr > MEMORY_SIZE or len > MEMORY_SIZE or buf_ptr +% len > MEMORY_SIZE) {
                // -EFAULT = -14
                vm.writeReg(10, @bitCast(@as(i32, -14)));
                return .continue_;
            }

            const buf = vm.memory[buf_ptr..][0..len];
            try writer.writeAll(buf);

            // Return bytes written in a0
            vm.writeReg(10, len);
            return .continue_;
        },
        .exit => {
            return .{ .exit = a0 };
        },
        _ => {
            // -ENOSYS = -38
            vm.writeReg(10, @bitCast(@as(i32, -38)));
            return .continue_;
        },
    }
}

/// Run the VM with automatic syscall handling. Returns exit code if the program
/// calls exit, or null if max_cycles is reached. If max_cycles is 0, runs without limit.
pub fn runWithSyscalls(vm: *Cpu, max_cycles: u64, writer: anytype) !?u32 {
    while (true) {
        if (max_cycles > 0 and vm.cycle_count >= max_cycles) return null;

        const result = try vm.step();
        switch (result) {
            .Continue => {},
            .Ecall => {
                const syscall_result = try handleSyscall(vm, writer);
                switch (syscall_result) {
                    .exit => |code| return code,
                    .continue_ => {},
                }
            },
            .Ebreak => return null,
        }
    }
}

test {
    _ = @import("syscall_test.zig");
}
