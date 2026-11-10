const std = @import("std");
const z = @import("zinn_infer");
test "inference-only package entry point, int8 and packed int4" {
    const A = z.Sequential(.{z.Dense(.{ .input = 2, .output = 1, .weights = &.{ 1, -2 }, .bias = &.{0} })});
    const B = z.Sequential(.{z.Dense(.{ .input = 2, .output = 1, .format = .int4, .packed_weights = &.{0xe1}, .bias = &.{0} })});
    var a: A.Workspace = .{};
    var b: B.Workspace = .{};
    var out_a: [1]i8 = undefined;
    var out_b: [1]i8 = undefined;
    A.infer(&.{ 3, 4 }, &out_a, &a);
    B.infer(&.{ 3, 4 }, &out_b, &b);
    try std.testing.expectEqual(@as(i8, -5), out_a[0]);
    try std.testing.expectEqualSlices(i8, &out_a, &out_b);
    try std.testing.expectEqual(@as(?usize, 0), z.argmax(&out_a));
}
