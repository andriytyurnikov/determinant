// Branch decoder tests — split into semantic groups
comptime {
    _ = @import("rtype_test.zig");
    _ = @import("alu_test.zig");
    _ = @import("shift_test.zig");
    _ = @import("load_store_test.zig");
    _ = @import("branch_test.zig");
    _ = @import("jump_test.zig");
    _ = @import("atomic_test.zig");
    _ = @import("system_test.zig");
    _ = @import("edge_test.zig");
}
