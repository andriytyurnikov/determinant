// rv32c tests — split into semantic groups
comptime {
    _ = @import("expand_q01_test.zig");
    _ = @import("expand_q2_test.zig");
    _ = @import("maxrange_test.zig");
    _ = @import("cpu_alu_test.zig");
    _ = @import("cpu_flow_test.zig");
    _ = @import("cpu_loadstore_test.zig");
    _ = @import("cpu_branch_test.zig");
    _ = @import("cpu_misc_test.zig");
}
