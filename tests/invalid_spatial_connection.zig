const z = @import("zinn");
const A = z.Conv2D(.{ .input = .{ .height = 2, .width = 3, .channels = 1 }, .output_channels = 1, .kernel = 1, .weights = &.{1}, .bias = &.{0} });
const B = z.AveragePool2D(.{ .input = .{ .height = 3, .width = 2, .channels = 1 }, .kernel = 1, .stride = 1 });
comptime {
    _ = z.Sequential(.{ A, B });
}
