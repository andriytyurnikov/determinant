// rv32c tests — split into semantic groups
comptime {
    _ = @import("rv32c_expand_q01_test.zig");
    _ = @import("rv32c_expand_q2_test.zig");
    _ = @import("rv32c_maxrange_test.zig");
    _ = @import("rv32c_cpu_alu_test.zig");
    _ = @import("rv32c_cpu_flow_test.zig");
    _ = @import("rv32c_cpu_loadstore_test.zig");
    _ = @import("rv32c_cpu_branch_test.zig");
    _ = @import("rv32c_cpu_misc_test.zig");
}
