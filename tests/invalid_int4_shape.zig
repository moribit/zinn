const z = @import("zinn");
comptime {
    _ = z.Dense(.{ .input = 3, .output = 1, .format = .int4, .packed_weights = &.{0x11}, .bias = &.{0} });
}
