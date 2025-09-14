comptime {
    _ = @import("cpu_init_test.zig");
    _ = @import("cpu_memory_test.zig");
    _ = @import("cpu_pipeline_test.zig");
    _ = @import("cpu_run_test.zig");
    _ = @import("cpu_determinism_test.zig");
    _ = @import("cpu_dispatch_test.zig");
    _ = @import("cpu_boundary_test.zig");
    _ = @import("cpu_store_upper_test.zig");
    _ = @import("cpu_atomic_test.zig");
    _ = @import("cpu_csr_test.zig");
    _ = @import("cpu_invariant_test.zig");
}
