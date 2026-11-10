//! Host drawing and MNIST normalization. This never enters the inference core.
const std = @import("std");
pub const side = 112;
pub const Point = struct { x: i16, y: i16 };
pub const Canvas = struct {
    pixels: [side * side]u8 = @splat(0),
    pub fn clear(self: *Canvas) void {
        @memset(&self.pixels, 0);
    }
    fn stamp(self: *Canvas, p: Point) bool {
        var changed = false;
        for (0..11) |iy| for (0..11) |ix| {
            const dx = @as(i32, @intCast(ix)) - 5;
            const dy = @as(i32, @intCast(iy)) - 5;
            const x = @as(i32, p.x) + dx;
            const y = @as(i32, p.y) + dy;
            if (x < 0 or y < 0 or x >= side or y >= side) continue;
            const d2 = dx * dx + dy * dy;
            const ink: u8 = if (d2 <= 16) 255 else if (d2 <= 25) 96 else 0;
            const at: usize = @intCast(y * side + x);
            if (ink > self.pixels[at]) {
                self.pixels[at] = ink;
                changed = true;
            }
        };
        return changed;
    }
    pub fn stroke(self: *Canvas, from: Point, to: Point) bool {
        // Input adapter supplies local bounded points; reject arbitrary outside input.
        if (from.x < 0 or from.y < 0 or to.x < 0 or to.y < 0 or from.x >= side or from.y >= side or to.x >= side or to.y >= side) return false;
        var x: i32 = from.x;
        var y: i32 = from.y;
        const dx: i32 = @intCast(@abs(@as(i32, to.x) - x));
        const dy: i32 = -@as(i32, @intCast(@abs(@as(i32, to.y) - y)));
        const sx: i32 = if (x < to.x) 1 else -1;
        const sy: i32 = if (y < to.y) 1 else -1;
        var err = dx + dy;
        var changed = false;
        while (true) {
            changed = self.stamp(.{ .x = @intCast(x), .y = @intCast(y) }) or changed;
            if (x == to.x and y == to.y) break;
            const twice = err * 2;
            if (twice >= dy) {
                err += dy;
                x += sx;
            }
            if (twice <= dx) {
                err += dx;
                y += sy;
            }
        }
        return changed;
    }
    /// Crop ink, fit within 20x20, center its mass in a 28x28 MNIST-style frame.
    /// Then use area-weighted 28->16 resize, matching Zinn's MNIST preprocessing.
    pub fn normalized(self: *const Canvas) ?[256]f32 {
        var left: usize = side;
        var top: usize = side;
        var right: usize = 0;
        var bottom: usize = 0;
        for (self.pixels, 0..) |v, i| if (v > 16) {
            left = @min(left, i % side);
            right = @max(right, i % side);
            top = @min(top, i / side);
            bottom = @max(bottom, i / side);
        };
        if (left == side) return null;
        const w = right - left + 1;
        const h = bottom - top + 1;
        const longest = @max(w, h);
        const nw = @max(1, (w * 20 + longest / 2) / longest);
        const nh = @max(1, (h * 20 + longest / 2) / longest);
        var frame: [28 * 28]f32 = @splat(0);
        for (0..nh) |y| for (0..nw) |x| {
            var sum: f32 = 0;
            // Integer area grid; output remains f32 until final quantization.
            for (y * h / nh..@min(h, ((y + 1) * h + nh - 1) / nh)) |sy| for (x * w / nw..@min(w, ((x + 1) * w + nw - 1) / nw)) |sx| {
                const wx = @min((sx + 1) * nw, (x + 1) * w) - @max(sx * nw, x * w);
                const wy = @min((sy + 1) * nh, (y + 1) * h) - @max(sy * nh, y * h);
                sum += @as(f32, @floatFromInt(self.pixels[(top + sy) * side + left + sx])) * @as(f32, @floatFromInt(wx * wy));
            };
            frame[(y + (28 - nh) / 2) * 28 + x + (28 - nw) / 2] = sum / @as(f32, @floatFromInt(w * h)) / 255;
        };
        var mass: f32 = 0;
        var mx: f32 = 0;
        var my: f32 = 0;
        for (frame, 0..) |v, i| {
            mass += v;
            mx += v * @as(f32, @floatFromInt(i % 28));
            my += v * @as(f32, @floatFromInt(i / 28));
        }
        const shift_x: i32 = @intFromFloat(@round(13.5 - mx / mass));
        const shift_y: i32 = @intFromFloat(@round(13.5 - my / mass));
        var centered: [28 * 28]f32 = @splat(0);
        for (frame, 0..) |v, i| {
            const x = @as(i32, @intCast(i % 28)) + shift_x;
            const y = @as(i32, @intCast(i / 28)) + shift_y;
            if (x >= 0 and y >= 0 and x < 28 and y < 28) centered[@intCast(y * 28 + x)] = v;
        }
        return area28to16(&centered);
    }
};

test "blank, continuous strokes, bounded edges and clear" {
    var c: Canvas = .{};
    try std.testing.expect(c.normalized() == null);
    try std.testing.expect(c.stroke(.{ .x = 0, .y = 0 }, .{ .x = 111, .y = 111 }));
    for (0..112) |i| try std.testing.expect(c.pixels[i * side + i] > 0);
    try std.testing.expect(!c.stroke(.{ .x = -1, .y = 0 }, .{ .x = 10, .y = 0 }));
    for (c.normalized().?) |v| try std.testing.expect(v >= 0 and v <= 1);
    c.clear();
    try std.testing.expect(c.normalized() == null);
}
test "normalization is translation invariant for the same unclipped stroke" {
    var a: Canvas = .{};
    var b: Canvas = .{};
    _ = a.stroke(.{ .x = 25, .y = 20 }, .{ .x = 40, .y = 70 });
    _ = b.stroke(.{ .x = 55, .y = 40 }, .{ .x = 70, .y = 90 });
    try std.testing.expectEqualSlices(f32, &a.normalized().?, &b.normalized().?);
}

fn area28to16(frame: *const [28 * 28]f32) [256]f32 {
    var output: [256]f32 = @splat(0);
    for (0..16) |y| for (0..16) |x| {
        var sum: f32 = 0;
        for (y * 28 / 16..((y + 1) * 28 + 15) / 16) |sy| for (x * 28 / 16..((x + 1) * 28 + 15) / 16) |sx| {
            const wx = @min((sx + 1) * 16, (x + 1) * 28) - @max(sx * 16, x * 28);
            const wy = @min((sy + 1) * 16, (y + 1) * 28) - @max(sy * 16, y * 28);
            sum += frame[sy * 28 + sx] * @as(f32, @floatFromInt(wx * wy));
        };
        output[y * 16 + x] = sum / (28 * 28);
    };
    return output;
}

test "28-to-16 area weights agree with the training preprocessing" {
    var bytes: [28 * 28]u8 = undefined;
    var frame: [28 * 28]f32 = undefined;
    for (&bytes, &frame, 0..) |*byte, *value, i| {
        byte.* = @intCast((i * 37) % 256);
        value.* = @as(f32, @floatFromInt(byte.*)) / 255;
    }
    var reference: [256]f32 = undefined;
    try @import("zinn_data").resizeArea(&bytes, 28, 28, &reference, 16, 16);
    for (area28to16(&frame), reference) |actual, expected|
        try std.testing.expectApproxEqAbs(expected, actual, 0.000001);
}
