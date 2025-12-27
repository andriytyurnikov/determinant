//! Compliance test hub — imports all per-extension test files.

comptime {
    _ = @import("rv32ui_test.zig");
    _ = @import("rv32um_test.zig");
    _ = @import("rv32ua_test.zig");
    _ = @import("rv32uc_test.zig");
    _ = @import("rv32uzba_test.zig");
    _ = @import("rv32uzbb_test.zig");
    _ = @import("rv32uzbs_test.zig");
}
