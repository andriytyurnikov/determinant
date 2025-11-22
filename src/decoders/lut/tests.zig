// LUT decoder tests — split into semantic groups
comptime {
    _ = @import("rtype_test.zig");
    _ = @import("ialu_test.zig");
    _ = @import("load_store_branch_test.zig");
    _ = @import("jump_test.zig");
    _ = @import("system_test.zig");
    _ = @import("operand_test.zig");
    _ = @import("edge_test.zig");
}
