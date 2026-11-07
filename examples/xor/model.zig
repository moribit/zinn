const z = @import("zinn");
// h0 = relu(x0-x1), h1 = relu(x1-x0); logits = [1-h0-h1, h0+h1].
pub const Model = z.Sequential(.{
    z.Dense(.{ .input = 2, .output = 2, .weights = &.{ 1, -1, -1, 1 }, .bias = &.{ 0, 0 }, .activation = .relu }),
    z.Dense(.{ .input = 2, .output = 2, .weights = &.{ -1, -1, 1, 1 }, .bias = &.{ 1, 0 } }),
});
pub const inputs = [4][2]i8{ .{ 0, 0 }, .{ 0, 1 }, .{ 1, 0 }, .{ 1, 1 } };
pub const expected = [4][2]i8{ .{ 1, 0 }, .{ 0, 1 }, .{ 0, 1 }, .{ 1, 0 } };
