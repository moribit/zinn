const z = @import("zinn");
comptime {
    _ = z.Dense(.{ .input = 1, .output = 1, .format = .int4, .packed_weights = &.{0xf1}, .bias = &.{0} });
}
