//! Presentation-only integer score scaling. No inference or probability calculation.
const std = @import("std");
pub const Summary = struct { min: i8, max: i8, margin: u16 };

/// Margin is top1 - top2 in raw logit units; duplicate maxima have margin zero.
pub fn analyze(values: *const [10]i8) Summary {
    var low = values[0];
    var first = values[0];
    var second: i8 = -128;
    for (values[1..]) |value| {
        low = @min(low, value);
        if (value >= first) {
            second = first;
            first = value;
        } else second = @max(second, value);
    }
    return .{ .min = low, .max = first, .margin = @intCast(@as(i16, first) - @as(i16, second)) };
}

/// Min-max relative width, rounded to nearest pixel (ties up).
/// Equal/inverted bounds are neutral empty bars. Out-of-range values clamp.
pub fn barWidth(value: i8, min_logit: i8, max_logit: i8, width: u16) u16 {
    const range = @as(i32, max_logit) - @as(i32, min_logit);
    if (range <= 0) return 0;
    const offset: u32 = @intCast(std.math.clamp(@as(i32, value) - min_logit, 0, range));
    const span: u32 = @intCast(range);
    // 255 * 65535 + 127 fits u32 for every i8/u16 input.
    return @intCast((offset * @as(u32, width) + span / 2) / span);
}

test "min/max, midpoint, rounding and full int8 range" {
    try std.testing.expectEqual(@as(u16, 78), barWidth(34, -35, 34, 78));
    try std.testing.expectEqual(@as(u16, 0), barWidth(-35, -35, 34, 78));
    try std.testing.expectEqual(@as(u16, 39), barWidth(0, -10, 10, 78));
    try std.testing.expectEqual(@as(u16, 3), barWidth(1, 0, 2, 5));
    try std.testing.expectEqual(@as(u16, 0), barWidth(-128, -128, 127, 65535));
    try std.testing.expectEqual(@as(u16, 65535), barWidth(127, -128, 127, 65535));
    try std.testing.expectEqual(@as(u16, 0), barWidth(10, -128, 127, 0));
    try std.testing.expectEqual(@as(u16, 0), barWidth(-128, -10, 10, 78));
    try std.testing.expectEqual(@as(u16, 78), barWidth(127, -10, 10, 78));
}
test "all equal logits are empty neutral bars with zero margin" {
    for ([_]i8{ -128, -5, 0, 5, 127 }) |value| {
        const values: [10]i8 = @splat(value);
        const summary = analyze(&values);
        try std.testing.expectEqual(@as(u16, 0), summary.margin);
        for (values) |v| try std.testing.expectEqual(@as(u16, 0), barWidth(v, summary.min, summary.max, 78));
    }
    try std.testing.expectEqual(@as(u16, 0), barWidth(0, 10, -10, 78));
}
test "negative/positive distributions, duplicate maxima and margin extremes" {
    const cases = .{
        .{ [_]i8{ -100, -31, -35, -13, -20, -1, -5, -8, -2, -12 }, @as(i8, -100), @as(i8, -1), @as(u16, 1) },
        .{ [_]i8{ 1, 2, 3, 4, 5, 34, 6, 7, 20, 12 }, @as(i8, 1), @as(i8, 34), @as(u16, 14) },
        .{ [_]i8{ -128, 127, -128, -128, -128, -128, -128, -128, -128, -128 }, @as(i8, -128), @as(i8, 127), @as(u16, 255) },
        .{ [_]i8{ -128, 127, 127, 0, 1, 2, 3, 4, 5, 6 }, @as(i8, -128), @as(i8, 127), @as(u16, 0) },
    };
    inline for (cases) |case| {
        const values: [10]i8 = case[0];
        const summary = analyze(&values);
        try std.testing.expectEqual(Summary{ .min = case[1], .max = case[2], .margin = case[3] }, summary);
        for (case[0]) |v| {
            const result = barWidth(v, summary.min, summary.max, 78);
            if (v == summary.max) try std.testing.expectEqual(@as(u16, 78), result);
            if (v == summary.min) try std.testing.expectEqual(@as(u16, 0), result);
        }
    }
}
test "exhaustive int8 bounds: widths stay bounded and monotonic" {
    for (0..256) |lo| for (lo..256) |hi| {
        const low: i8 = @intCast(@as(i16, @intCast(lo)) - 128);
        const high: i8 = @intCast(@as(i16, @intCast(hi)) - 128);
        var previous: u16 = 0;
        for (lo..hi + 1) |i| {
            const value: i8 = @intCast(@as(i16, @intCast(i)) - 128);
            const result = barWidth(value, low, high, 78);
            try std.testing.expect(result >= previous and result <= 78);
            try std.testing.expectEqual(result, barWidth(value, low, high, 78));
            previous = result;
        }
    };
}
