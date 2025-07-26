// rv32a tests — split into semantic groups
comptime {
    _ = @import("rv32a_decode_lrsc_test.zig");
    _ = @import("rv32a_amo_test.zig");
}
