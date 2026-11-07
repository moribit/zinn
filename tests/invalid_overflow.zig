const z = @import("zinn");
const A = z.Dense(.{ .input = 1, .output = 1, .weights = &.{1}, .bias = &.{2147483647} });
comptime {
    _ = A;
}
