// rv32m tests — split into semantic groups
comptime {
    _ = @import("rv32m_mul_test.zig");
    _ = @import("rv32m_div_test.zig");
}
