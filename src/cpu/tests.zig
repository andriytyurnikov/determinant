comptime {
    _ = @import("init_test.zig");
    _ = @import("memory_test.zig");
    _ = @import("pipeline_test.zig");
    _ = @import("run_test.zig");
    _ = @import("determinism_test.zig");
    _ = @import("atomic_test.zig");
    _ = @import("csr_test.zig");
    _ = @import("invariant_test.zig");
    _ = @import("integration_test.zig");
    _ = @import("recovery_test.zig");
    _ = @import("state_test.zig");
    _ = @import("decode_cache_test.zig");
    _ = @import("fault_test.zig");
    _ = @import("csr_table_test.zig");
    _ = @import("aliasing_test.zig");
    _ = @import("wraparound_test.zig");
    _ = @import("host_api_test.zig");
}
