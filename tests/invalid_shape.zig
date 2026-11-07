const z = @import("zinn");
const A = z.Dense(.{ .input = 2, .output = 1, .weights = &.{1}, .bias = &.{0} });
comptime {
    _ = A;
}
