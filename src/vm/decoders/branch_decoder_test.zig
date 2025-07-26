// branch_decoder tests — split into semantic groups
comptime {
    _ = @import("branch_decoder_rtype_test.zig");
    _ = @import("branch_decoder_itype_test.zig");
    _ = @import("branch_decoder_shift_test.zig");
    _ = @import("branch_decoder_uj_test.zig");
    _ = @import("branch_decoder_edge_test.zig");
}
