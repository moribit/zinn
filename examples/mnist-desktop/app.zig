const std = @import("std");
const m = @import("mimoc_ui");
const generated = @import("trained_model");
const drawing = @import("canvas.zig");
pub const width = 480;
pub const height = 272;
pub const Model = generated.Model;
comptime {
    if (Model.input_len != 256 or Model.output_len != 10) @compileError("MNIST desktop expects a 16x16 input and ten digit logits");
}
const Ui = m.ui.Ui(u16, m.profiles.desktop);
pub const canvas_rect = m.geometry.Rect{ .x = 24, .y = 64, .w = drawing.side, .h = drawing.side };
pub const App = struct {
    canvas: drawing.Canvas = .{},
    workspace: Model.Workspace = .{},
    input: [256]i8 = @splat(0),
    logits: [10]i8 = @splat(0),
    prediction: ?u8 = null,
    drawing_active: bool = false,
    previous: ?drawing.Point = null,
    sample_index: usize = 0,
    sample_mode: bool = false,
    inference_count: usize = 0,
    display: Ui.Runtime = .{},
    pixels: [width * ((height + 7) / 8)]u8 = @splat(0),
    labels: [16][96]u8 = undefined,
    label_count: usize = 0,
    fn text(self: *App, comptime fmt: []const u8, args: anytype) []const u8 {
        const result = std.fmt.bufPrint(&self.labels[self.label_count], fmt, args) catch unreachable;
        self.label_count += 1;
        return result;
    }
    pub fn clear(self: *App) void {
        self.canvas.clear();
        @memset(&self.input, 0);
        @memset(&self.logits, 0);
        self.prediction = null;
        self.sample_mode = false;
        self.stopStroke();
    }
    fn infer(self: *App) void {
        Model.infer(&self.input, &self.logits, &self.workspace);
        var best: u8 = 0;
        for (self.logits, 0..) |v, i| if (v > self.logits[best]) {
            best = @intCast(i);
        };
        self.prediction = best;
        self.inference_count += 1;
    }
    fn classify(self: *App) void {
        const values = self.canvas.normalized() orelse {
            self.prediction = null;
            return;
        };
        for (&self.input, values) |*out, value| {
            out.* = @intFromFloat(std.math.clamp(@round(value / generated.input_scale), -128, 127));
        }
        self.sample_mode = false;
        self.infer();
    }
    pub fn sample(self: *App) void {
        self.stopStroke();
        self.input = generated.inputs[self.sample_index % generated.inputs.len];
        self.sample_index += 1;
        for (&self.canvas.pixels, 0..) |*pixel, i| {
            const x = (i % drawing.side) * 16 / drawing.side;
            const y = (i / drawing.side) * 16 / drawing.side;
            pixel.* = @intFromFloat(std.math.clamp(@as(f32, @floatFromInt(self.input[y * 16 + x])) * generated.input_scale * 255, 0, 255));
        }
        self.sample_mode = true;
        self.infer();
    }
    pub fn stopStroke(self: *App) void {
        self.drawing_active = false;
        self.previous = null;
    }
    pub fn focusLost(self: *App) void {
        self.stopStroke();
        self.display.cancelInput();
    }
    fn local(point: m.geometry.Point) ?drawing.Point {
        if (!canvas_rect.contains(point.x, point.y)) return null;
        return .{ .x = point.x - canvas_rect.x, .y = point.y - canvas_rect.y };
    }
    fn move(self: *App, point: m.geometry.Point) void {
        const p = local(point) orelse {
            self.previous = null;
            return;
        };
        const changed = self.canvas.stroke(self.previous orelse p, p);
        self.previous = p;
        if (changed) self.classify();
    }
    pub fn receive(self: *App, event: m.input.InputEvent) void {
        const action = self.display.dispatch(event);
        if (action.activated) {
            if (action.target == Ui.childId(Ui.rootId(1), 10)) self.clear();
            if (action.target == Ui.childId(Ui.rootId(1), 11)) self.sample();
        }
        switch (event) {
            .pointer_down => |p| if (local(p) != null) {
                if (self.sample_mode) self.clear();
                self.drawing_active = true;
                self.move(p);
            },
            .pointer_move => |p| if (self.drawing_active) {
                self.move(p);
            },
            .pointer_up => |p| {
                if (self.drawing_active) self.move(p);
                self.stopStroke();
            },
            .key_down => |key| if (key == .escape or key == .backspace or key == .delete) {
                self.clear();
            },
            else => {},
        }
        self.render();
    }
    pub fn render(self: *App) void {
        self.label_count = 0;
        self.display.viewport = .{ .w = width, .h = height };
        var ui = Ui.begin(&self.display);
        var root = ui.stack(1, .{});
        ui.textWith(2, "ZINN / HANDWRITTEN DIGITS", .{ .offset = .{ .x = 24, .y = 16 } });
        ui.textWith(3, "PURE ZIG / MIMOC UI", .{ .offset = .{ .x = 324, .y = 16 } });
        ui.textWith(4, "DRAW ONE DIGIT", .{ .offset = .{ .x = 24, .y = 44 } });
        ui.textWith(5, "16X16 INPUT", .{ .offset = .{ .x = 156, .y = 44 } });
        ui.textWith(6, "PREDICTION", .{ .offset = .{ .x = 252, .y = 44 } });
        ui.textWith(7, "INT8 LOGITS", .{ .offset = .{ .x = 348, .y = 44 } });
        ui.textWith(8, if (self.prediction == null) "WRITE A DIGIT TO BEGIN" else if (self.sample_mode) "MNIST VALIDATION SAMPLE" else "LIVE / UPDATES AS YOU DRAW", .{ .offset = .{ .x = 24, .y = 190 } });
        ui.buttonWith(10, "CLEAR", .{ .offset = .{ .x = 24, .y = 214 }, .size = .{ .w = 64, .h = 20 } });
        ui.buttonWith(11, "SAMPLE", .{ .offset = .{ .x = 100, .y = 214 }, .size = .{ .w = 64, .h = 20 } });
        ui.textWith(12, "DRAG TO DRAW / ESC TO CLEAR", .{ .offset = .{ .x = 24, .y = 250 } });
        ui.textWith(13, self.text("MLP32 INT8 / ID {x}", .{generated.model_id}), .{ .offset = .{ .x = 276, .y = 250 } });
        root.end();
        ui.finish();
        m.headless.render(&self.display, &self.pixels, width, height) catch unreachable;
        var surface = m.surface.Mono1.init(&self.pixels, width, height) catch unreachable;
        var r = m.mono1.Renderer.init(&surface);
        r.hline(24, 32, width - 48, true);
        r.rect(.{ .x = canvas_rect.x - 2, .y = canvas_rect.y - 2, .w = canvas_rect.w + 4, .h = canvas_rect.h + 4 }, true);
        for (self.canvas.pixels, 0..) |v, i| {
            const x = i % drawing.side;
            const y = i / drawing.side;
            if (dither(v, x, y)) r.pixel(canvas_rect.x + @as(i16, @intCast(x)), canvas_rect.y + @as(i16, @intCast(y)), true);
        }
        r.rect(.{ .x = 154, .y = 62, .w = 52, .h = 52 }, true);
        for (0..48) |y| for (0..48) |x| {
            const q = self.input[(y / 3) * 16 + x / 3];
            const v: u8 = @intFromFloat(std.math.clamp(@as(f32, @floatFromInt(q)) * generated.input_scale * 255, 0, 255));
            if (dither(v, x, y)) r.pixel(@as(i16, @intCast(x)) + 156, @as(i16, @intCast(y)) + 64, true);
        };
        if (self.prediction) |digit| {
            const columns = m.font.glyph('0' + digit);
            for (columns, 0..) |bits, x| for (0..7) |y| {
                if (bits & (@as(u8, 1) << @as(u3, @intCast(y))) != 0)
                    r.fillRect(.{ .x = 252 + @as(i16, @intCast(x)) * 8, .y = 66 + @as(i16, @intCast(y)) * 8, .w = 8, .h = 8 }, true);
            };
            m.font.draw(&r, .tiny5x7, 252, 144, "DIGIT 0-9", true);
            for (self.logits, 0..) |value, i| {
                const y: i16 = 66 + @as(i16, @intCast(i)) * 14;
                m.font.draw(&r, .tiny5x7, 324, y, if (value >= 0) self.text("{d} {d: >4}", .{ i, @as(u8, @intCast(value)) }) else self.text("{d} {d: >4}", .{ i, value }), true);
                r.rect(.{ .x = 376, .y = y, .w = 80, .h = 7 }, true);
                const fill: i16 = @intCast(@divTrunc((@as(i32, value) + 128) * 78, 255));
                r.fillRect(.{ .x = 377, .y = y + 1, .w = fill, .h = 5 }, true);
                if (i == digit) r.rect(.{ .x = 316, .y = y - 2, .w = 144, .h = 12 }, true);
            }
        } else m.font.draw(&r, .tiny5x7, 252, 78, "--", true);
        m.font.draw(&r, .tiny5x7, 324, 218, "NOT PROBABILITIES", true);
    }
};
fn dither(value: u8, x: usize, y: usize) bool {
    const thresholds = [4][4]u8{ .{ 0, 8, 2, 10 }, .{ 12, 4, 14, 6 }, .{ 3, 11, 1, 9 }, .{ 15, 7, 13, 5 } };
    return value > @as(u16, thresholds[y % 4][x % 4]) * 16 + 7;
}
test "sample logits equal generated fixture, independent buffers and clear" {
    var app: App = .{};
    app.render();
    try std.testing.expect(app.prediction == null);
    for (generated.expected) |expected| {
        app.sample();
        try std.testing.expectEqualSlices(i8, &expected, &app.logits);
    }
    app.clear();
    try std.testing.expect(app.prediction == null);
    try std.testing.expectEqual(@as(?[256]f32, null), app.canvas.normalized());
}
test "drag classifies immediately, outside/focus release stop drawing, clear button" {
    var app: App = .{};
    app.render();
    app.receive(.{ .pointer_move = .{ .x = 60, .y = 80 } });
    try std.testing.expectEqual(@as(usize, 0), app.inference_count);
    app.receive(.{ .pointer_down = .{ .x = 50, .y = 80 } });
    try std.testing.expect(app.prediction != null);
    const before = app.inference_count;
    app.receive(.{ .pointer_move = .{ .x = 80, .y = 150 } });
    try std.testing.expect(app.inference_count > before);
    app.receive(.{ .pointer_up = .{ .x = -20, .y = -20 } });
    try std.testing.expect(!app.drawing_active);
    app.receive(.{ .pointer_down = .{ .x = 60, .y = 80 } });
    app.focusLost();
    try std.testing.expect(!app.drawing_active);
    app.receive(.{ .pointer_down = .{ .x = 30, .y = 220 } });
    app.receive(.{ .pointer_up = .{ .x = 30, .y = 220 } });
    try std.testing.expect(app.prediction == null);
}
test {
    _ = drawing;
}

test "a seven drawn through the pointer adapter is classified as seven" {
    var app: App = .{};
    app.render();
    app.receive(.{ .pointer_down = .{ .x = 40, .y = 84 } });
    app.receive(.{ .pointer_move = .{ .x = 115, .y = 84 } });
    app.receive(.{ .pointer_up = .{ .x = 115, .y = 84 } });
    app.receive(.{ .pointer_down = .{ .x = 115, .y = 84 } });
    app.receive(.{ .pointer_move = .{ .x = 63, .y = 160 } });
    app.receive(.{ .pointer_up = .{ .x = 63, .y = 160 } });
    try std.testing.expectEqual(@as(?u8, 7), app.prediction);
}
