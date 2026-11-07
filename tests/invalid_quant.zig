const z = @import("zinn");
const A = z.Dense(.{ .input = 1, .output = 1, .weights = &.{1}, .bias = &.{0}, .quant = .{ .multiplier = 0 } });
comptime {
    _ = A;
}
