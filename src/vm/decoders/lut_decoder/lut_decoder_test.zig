// lut_decoder tests — split into semantic groups
comptime {
    _ = @import("lut_decoder_rtype_test.zig");
    _ = @import("lut_decoder_ialu_test.zig");
    _ = @import("lut_decoder_mem_test.zig");
    _ = @import("lut_decoder_system_test.zig");
}
