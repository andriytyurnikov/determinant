comptime {
    _ = @import("init_test.zig");
    _ = @import("memory_test.zig");
    _ = @import("pipeline_test.zig");
    _ = @import("run_test.zig");
    _ = @import("determinism_test.zig");
    _ = @import("dispatch_test.zig");
    _ = @import("boundary_test.zig");
    _ = @import("store_upper_test.zig");
    _ = @import("atomic_test.zig");
    _ = @import("csr_test.zig");
    _ = @import("invariant_test.zig");
    _ = @import("integration_test.zig");
}
