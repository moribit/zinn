const std = @import("std");
const z = @import("root.zig");
const expect = std.testing.expectEqual;
test "rounding, signed boundaries, saturation and relu" {
    try expect(@as(i8, 2), z.quant.requantize(3, .{ .shift = 1 }));
    try expect(@as(i8, -2), z.quant.requantize(-3, .{ .shift = 1 }));
    try expect(@as(i8, 1), z.quant.requantize(2, .{ .shift = 1 }));
    try expect(@as(i8, -1), z.quant.requantize(-2, .{ .shift = 1 }));
    try expect(@as(i8, 127), z.quant.requantize(std.math.maxInt(i32), .{ .multiplier = 65535 }));
    try expect(@as(i8, -128), z.quant.requantize(std.math.minInt(i32), .{ .multiplier = 65535 }));
    try expect(@as(i8, -1), z.quant.requantize(std.math.minInt(i32), .{ .shift = 31 }));
    try expect(@as(i8, -7), z.quant.relu(-20, -7));
    try expect(@as(i8, 20), z.quant.relu(20, -7));
}
test "requantization matches independent division reference" {
    for (0..8) |shift| {
        var value: i32 = -1000;
        while (value <= 1000) : (value += 1) {
            const p: z.quant.Params = .{ .multiplier = 13, .shift = @intCast(shift), .output_zero = -3 };
            const divisor = @as(i64, 1) << @intCast(shift);
            const product = @as(i64, value) * 13;
            const magnitude = @abs(product);
            const rounded = (magnitude + @as(u64, @intCast(@divTrunc(divisor, 2)))) / @as(u64, @intCast(divisor));
            const signed = (if (value < 0) -@as(i64, @intCast(rounded)) else @as(i64, @intCast(rounded))) - 3;
            try expect(@as(i8, @intCast(@max(-128, @min(127, signed)))), z.quant.requantize(value, p));
        }
    }
}
test "dense matches int64 reference including nonzero input zero" {
    const weights = [_]i8{ -128, 127, 3, -7, 127, -128, -4, 5 };
    const biases = [_]i32{ 123, -999 };
    const p: z.quant.Params = .{ .input_zero = -11, .output_zero = 9, .multiplier = 3, .shift = 10 };
    const L = z.Dense(.{ .input = 4, .output = 2, .weights = &weights, .bias = &biases, .quant = p });
    var seed: u32 = 42;
    for (0..256) |_| {
        var input: [4]i8 = undefined;
        for (&input) |*x| {
            seed = seed *% 1664525 +% 1013904223;
            x.* = @bitCast(@as(u8, @truncate(seed >> 16)));
        }
        var actual: [2]i8 = undefined;
        L.run(&input, &actual);
        for (0..2) |row| {
            var acc: i64 = biases[row];
            for (input, 0..) |x, i| acc += (@as(i64, x) + 11) * weights[row * 4 + i];
            const product = acc * 3;
            const rounded: i64 = @intCast((@abs(product) + 512) / 1024);
            const expected = (if (product < 0) -rounded else rounded) + 9;
            try expect(@as(i8, @intCast(@max(-128, @min(127, expected)))), actual[row]);
        }
    }
}
test "multilayer XOR golden vectors and reusable workspace" {
    const M = z.Sequential(.{
        z.Dense(.{ .input = 2, .output = 2, .weights = &.{ 1, -1, -1, 1 }, .bias = &.{ 0, 0 }, .activation = .relu }),
        z.Dense(.{ .input = 2, .output = 2, .weights = &.{ -1, -1, 1, 1 }, .bias = &.{ 1, 0 } }),
    });
    var ws: M.Workspace = undefined;
    const inputs = [4][2]i8{ .{ 0, 0 }, .{ 0, 1 }, .{ 1, 0 }, .{ 1, 1 } };
    const golden = [4][2]i8{ .{ 1, 0 }, .{ 0, 1 }, .{ 0, 1 }, .{ 1, 0 } };
    for (inputs, golden) |input, expected| {
        var out: [2]i8 = undefined;
        M.infer(&input, &out, &ws);
        try std.testing.expectEqualSlices(i8, &expected, &out);
    }
    try expect(@as(usize, 4), M.workspace_bytes);
}
test "tensor and argmax tie/empty/negative" {
    var t: z.Tensor(i8, &.{ 2, 3 }) = .{ .data = @splat(0) };
    t.data[5] = 7;
    try expect(@as(usize, 6), t.data.len);
    try expect(@as(?usize, null), z.argmax(&.{}));
    try expect(@as(?usize, 1), z.argmax(&.{ -9, -2, -2 }));
}

test "unequal layer widths, output alias, nonzero relu zero and saturation" {
    const M = z.Sequential(.{
        z.Dense(.{ .input = 3, .output = 1, .weights = &.{ 127, 127, 127 }, .bias = &.{0}, .activation = .relu, .quant = .{ .output_zero = -3 } }),
        z.Dense(.{ .input = 1, .output = 3, .weights = &.{ 1, -1, 0 }, .bias = &.{ 0, 0, 0 }, .quant = .{ .input_zero = -3 } }),
    });
    var ws: M.Workspace = undefined;
    var data = [3]i8{ 127, 127, 127 };
    M.infer(&data, &data, &ws);
    try std.testing.expectEqualSlices(i8, &.{ 127, -128, 0 }, &data);
    data = .{ -128, -128, -128 };
    M.infer(&data, &data, &ws);
    try std.testing.expectEqualSlices(i8, &.{ 0, 0, 0 }, &data);
}
