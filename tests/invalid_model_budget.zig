const z = @import("zinn");
const M = z.Sequential(.{z.Dense(.{ .input = 2, .output = 1, .weights = &.{ 1, 1 }, .bias = &.{0} })});
comptime {
    M.checkBudget(.{ .flash_bytes = 65 });
}
