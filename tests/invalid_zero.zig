const z = @import("zinn");
const A = z.Dense(.{ .input = 1, .output = 1, .weights = &.{1}, .bias = &.{0}, .quant = .{ .output_zero = 1 } });
const B = z.Dense(.{ .input = 1, .output = 1, .weights = &.{1}, .bias = &.{0} });
comptime {
    _ = z.Sequential(.{ A, B });
}
