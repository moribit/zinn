const z = @import("zinn");
comptime {
    _ = z.Dense(.{ .input = 1, .output = 1, .weights = &.{1}, .bias = &.{0}, .quant = .{ .input_scale = 1, .weight_scale = 1, .output_scale = 2 } });
}
