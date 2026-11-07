const z = @import("zinn");
comptime {
    _ = z.Conv2D(.{ .input = .{ .height = 1, .width = 1, .channels = 1 }, .output_channels = 1, .kernel = 1, .weights = &.{1}, .bias = &.{2147483647} });
}
