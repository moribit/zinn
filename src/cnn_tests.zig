const std = @import("std");
const z = @import("root.zig");
test "int4 all signed nibbles, odd packing and dense agrees with int8" {
    var all: [16]i8 = undefined;
    for (&all, 0..) |*v, i| v.* = @intCast(@as(i32, @intCast(i)) - 8);
    var encoded: [8]u8 = undefined;
    try z.lowbit.encode(&all, &encoded);
    for (all, 0..) |v, i| try std.testing.expectEqual(v, z.lowbit.get(.int4, &.{}, &encoded, i));
    const weights = [5]i8{ -8, 7, -1, 0, 3 };
    var bytes: [3]u8 = undefined;
    try z.lowbit.encode(&weights, &bytes);
    try std.testing.expectEqualSlices(u8, &.{ 0x78, 0x0f, 0x03 }, &bytes);
    for (weights, 0..) |w, i| try std.testing.expectEqual(w, z.lowbit.get(.int4, &.{}, &bytes, i));
    try std.testing.expectError(error.Int4OutOfRange, z.lowbit.encode(&.{8}, bytes[0..1]));
    const A = z.Dense(.{ .input = 5, .output = 1, .weights = &weights, .bias = &.{4} });
    const B = z.Dense(.{ .input = 5, .output = 1, .format = .int4, .packed_weights = &.{ 0x78, 0x0f, 0x03 }, .bias = &.{4} });
    var a: [1]i8 = undefined;
    var b: [1]i8 = undefined;
    A.run(&.{ -5, 4, 7, 2, 1 }, &a);
    B.run(&.{ -5, 4, 7, 2, 1 }, &b);
    try std.testing.expectEqualSlices(i8, &.{68}, &a);
    try std.testing.expectEqualSlices(i8, &a, &b);
}
test "HWC convolution channels, padding zero point and packed weights" {
    const C = z.Conv2D(.{ .input = .{ .height = 2, .width = 2, .channels = 2 }, .output_channels = 2, .kernel = 1, .weights = &.{ 1, 2, -1, 1 }, .bias = &.{ 0, 1 } });
    const P = z.Conv2D(.{ .input = .{ .height = 2, .width = 2, .channels = 2 }, .output_channels = 2, .kernel = 1, .format = .int4, .packed_weights = &.{ 0x21, 0x1f }, .bias = &.{ 0, 1 } });
    var a: [8]i8 = undefined;
    var b: [8]i8 = undefined;
    C.run(&.{ 1, 2, 3, 4, 5, 6, 7, 8 }, &a);
    P.run(&.{ 1, 2, 3, 4, 5, 6, 7, 8 }, &b);
    try std.testing.expectEqualSlices(i8, &.{ 5, 2, 11, 2, 17, 2, 23, 2 }, &a);
    try std.testing.expectEqualSlices(i8, &a, &b);
    const Pad = z.Conv2D(.{ .input = .{ .height = 1, .width = 1, .channels = 1 }, .output_channels = 1, .kernel = 3, .padding = 1, .weights = &.{ 1, 1, 1, 1, 1, 1, 1, 1, 1 }, .bias = &.{0}, .quant = .{ .input_zero = 5 } });
    var padded: [1]i8 = undefined;
    Pad.run(&.{7}, &padded);
    try std.testing.expectEqual(@as(i8, 2), padded[0]);
}
test "average pooling negative ties, stride and channels" {
    const Pool = z.AveragePool2D(.{ .input = .{ .height = 2, .width = 2, .channels = 2 } });
    var out: [2]i8 = undefined;
    Pool.run(&.{ -1, 1, -1, 1, 0, 0, 0, 0 }, &out);
    try std.testing.expectEqualSlices(i8, &.{ -1, 1 }, &out);
}
test "CNN reverse pass with shared filters and pooling agrees with finite differences" {
    const S = z.ImageDefinition(.{ .height = 4, .width = 4, .channels = 1 }, &.{
        .{ .kind = .conv2d, .units = 2, .kernel = 2, .activation = .relu },
        .{ .kind = .average_pool2d, .kernel = 2, .stride = 1 },
        .{ .units = 2 },
    });
    const T = z.Trainer(S);
    var model = T.init(17);
    const sample: T.Sample = .{ .input = .{ 1, 0, 2, 1, 0, 1, 1, 0, 2, 0, 1, 1, 1, 0, 0, 2 }, .target = .{ 0, 1 } };
    var gradient: [S.parameter_count]f32 = undefined;
    _ = model.gradientWithLoss(sample, &gradient, .cross_entropy);
    for (&model.parameters, 0..) |*p, i| {
        const old = p.*;
        var scratch: [S.parameter_count]f32 = undefined;
        p.* = old + 0.001;
        const plus = model.gradientWithLoss(sample, &scratch, .cross_entropy);
        p.* = old - 0.001;
        const minus = model.gradientWithLoss(sample, &scratch, .cross_entropy);
        p.* = old;
        try std.testing.expectApproxEqAbs(gradient[i], (plus - minus) / 0.002, 0.002);
    }
}

test "convolution stride and padding use real zero at borders" {
    const C = z.Conv2D(.{ .input = .{ .height = 3, .width = 3, .channels = 1 }, .output_channels = 1, .kernel = 2, .stride = 2, .padding = 1, .weights = &.{ 1, 1, 1, 1 }, .bias = &.{0}, .quant = .{ .input_zero = 3 } });
    var output: [4]i8 = undefined;
    C.run(&.{ 1, 2, 3, 4, 5, 6, 7, 8, 9 }, &output);
    try std.testing.expectEqualSlices(i8, &.{ -2, -1, 5, 16 }, &output);
}

test "pool rounding is centered on the quantization zero point" {
    const Pool = z.AveragePool2D(.{ .input = .{ .height = 2, .width = 2, .channels = 1 }, .zero = 5 });
    var out: [1]i8 = undefined;
    Pool.run(&.{ 4, 5, 4, 5 }, &out);
    try std.testing.expectEqual(@as(i8, 4), out[0]);
}

test "randomized int8 and int4 convolution match independent HWC oracle" {
    const weights = comptime blk: {
        var w: [54]i8 = undefined;
        for (&w, 0..) |*v, i| v.* = @intCast(@as(i32, @intCast(i % 15)) - 7);
        break :blk w;
    };
    const bytes = comptime blk: {
        var v: [27]u8 = undefined;
        z.lowbit.encode(&weights, &v) catch unreachable;
        break :blk v;
    };
    const p: z.quant.Params = .{ .multiplier = 3, .shift = 5, .input_zero = -7, .output_zero = 3 };
    const C = z.Conv2D(.{ .input = .{ .height = 3, .width = 4, .channels = 2 }, .output_channels = 3, .kernel = 3, .stride = 2, .padding = 1, .weights = &weights, .bias = &.{ 123, -71, 0 }, .quant = p, .activation = .relu });
    const P = z.Conv2D(.{ .input = .{ .height = 3, .width = 4, .channels = 2 }, .output_channels = 3, .kernel = 3, .stride = 2, .padding = 1, .format = .int4, .packed_weights = &bytes, .bias = &.{ 123, -71, 0 }, .quant = p, .activation = .relu });
    var rng: u32 = 117;
    for (0..128) |_| {
        var input: [24]i8 = undefined;
        for (&input) |*v| {
            rng = rng *% 1664525 +% 1013904223;
            v.* = @bitCast(@as(u8, @truncate(rng >> 16)));
        }
        var actual: [12]i8 = undefined;
        var packed_actual: [12]i8 = undefined;
        C.run(&input, &actual);
        P.run(&input, &packed_actual);
        for (0..2) |y| for (0..2) |x| for (0..3) |c| {
            var acc: i64 = ([_]i32{ 123, -71, 0 })[c];
            for (0..3) |ky| for (0..3) |kx| {
                const iy = @as(i32, @intCast(y * 2 + ky)) - 1;
                const ix = @as(i32, @intCast(x * 2 + kx)) - 1;
                if (iy >= 0 and iy < 3 and ix >= 0 and ix < 4) for (0..2) |channel| {
                    const i = (@as(usize, @intCast(iy)) * 4 + @as(usize, @intCast(ix))) * 2 + channel;
                    const wi = ((c * 3 + ky) * 3 + kx) * 2 + channel;
                    acc += (@as(i64, input[i]) + 7) * weights[wi];
                };
            };
            const product = acc * 3;
            const magnitude = (@abs(product) + 16) / 32;
            const signed = (if (product < 0) -@as(i64, @intCast(magnitude)) else @as(i64, @intCast(magnitude))) + 3;
            try std.testing.expectEqual(@as(i8, @intCast(@max(3, @min(127, signed)))), actual[(y * 2 + x) * 3 + c]);
        };
        try std.testing.expectEqualSlices(i8, &actual, &packed_actual);
    }
}
