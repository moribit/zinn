const std = @import("std");
const m = @import("mimoc_ui");
const generated = @import("trained_model");
const drawing = @import("canvas.zig");
pub const inspector = @import("inspector.zig");
const scores = @import("logits.zig");
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
    trace: Model.Trace = .{},
    inspection: inspector.State = .{},
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
        self.trace = .{};
        self.inspection.clear();
        @memset(&self.input, 0);
        @memset(&self.logits, 0);
        self.prediction = null;
        self.sample_mode = false;
        self.stopStroke();
    }
    fn infer(self: *App) void {
        Model.inferTraced(&self.input, &self.logits, &self.workspace, &self.trace);
        self.inspection.restart();
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
            inline for (0..3) |i| if (action.target == Ui.childId(Ui.rootId(1), 20 + i)) {
                self.stopStroke();
                self.inspection.mode = @fromBackingInt(@intCast(i));
                self.inspection.restart();
            };
            if (self.inspection.mode != .play) self.inspection.control(action.target.?);
            if (action.target == Ui.childId(Ui.rootId(1), 10)) self.clear();
            if (action.target == Ui.childId(Ui.rootId(1), 11)) self.sample();
        }
        if (self.inspection.mode != .play) {
            switch (event) {
                .pointer_down => |p| self.inspection.select(p),
                .key_down => |key| if (key == .escape or key == .backspace or key == .delete) {
                    self.clear();
                },
                else => {},
            }
            self.render();
            return;
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
    /// Absolute monotonic milliseconds supplied by platform; no inference on ticks.
    pub fn tick(self: *App, now: u32) bool {
        if (!self.inspection.tick(now, self.prediction != null)) return false;
        self.render();
        return true;
    }
    pub fn render(self: *App) void {
        if (self.inspection.mode != .play) {
            inspector.render(self);
            return;
        }
        self.label_count = 0;
        self.display.viewport = .{ .w = width, .h = height };
        var ui = Ui.begin(&self.display);
        var root = ui.stack(1, .{});
        ui.textWith(2, "ZINN / HANDWRITTEN DIGITS", .{ .offset = .{ .x = 24, .y = 16 } });
        ui.textWith(4, "DRAW ONE DIGIT", .{ .offset = .{ .x = 24, .y = 44 } });
        ui.textWith(5, "16X16 INPUT", .{ .offset = .{ .x = 156, .y = 44 } });
        ui.textWith(6, "PREDICTION", .{ .offset = .{ .x = 252, .y = 44 } });
        ui.textWith(7, "INT8 LOGITS", .{ .offset = .{ .x = 348, .y = 44 } });
        ui.textWith(8, if (self.prediction == null) "WRITE A DIGIT TO BEGIN" else if (self.sample_mode) "MNIST VALIDATION SAMPLE" else "LIVE / UPDATES AS YOU DRAW", .{ .offset = .{ .x = 24, .y = 190 } });
        ui.buttonWith(10, "CLEAR", .{ .offset = .{ .x = 24, .y = 214 }, .size = .{ .w = 64, .h = 20 }, .text_alignment = .center, .text_vertical_alignment = .center });
        ui.buttonWith(11, "SAMPLE", .{ .offset = .{ .x = 100, .y = 214 }, .size = .{ .w = 64, .h = 20 }, .text_alignment = .center, .text_vertical_alignment = .center });
        ui.textWith(12, "DRAG TO DRAW / ESC TO CLEAR", .{ .offset = .{ .x = 24, .y = 250 } });
        ui.textWith(13, self.text("MLP32 INT8 / ID {x}", .{generated.model_id}), .{ .offset = .{ .x = 276, .y = 250 } });
        inspector.navigator(&ui);
        root.end();
        ui.finish();
        m.headless.render(&self.display, &self.pixels, width, height) catch unreachable;
        var surface = m.surface.Mono1.init(&self.pixels, width, height) catch unreachable;
        var r = m.mono1.Renderer.init(&surface);
        r.hline(24, 32, width - 48, true);
        r.hline(292, 30, 52, true);
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
            const distribution = scores.analyze(&self.logits);
            for (self.logits, 0..) |value, i| {
                const y: i16 = 66 + @as(i16, @intCast(i)) * 14;
                m.font.draw(&r, .tiny5x7, 324, y, if (value >= 0) self.text("{d} {d: >4}", .{ i, @as(u8, @intCast(value)) }) else self.text("{d} {d: >4}", .{ i, value }), true);
                r.rect(.{ .x = 376, .y = y, .w = 80, .h = 7 }, true);
                const fill: i16 = @intCast(scores.barWidth(value, distribution.min, distribution.max, 78));
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
    _ = scores;
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

test "sample bars match relative widths; logits, predictions and clear remain unchanged" {
    var app: App = .{};
    app.render();
    var previous_widths: [10]u16 = @splat(0);
    var changed = false;
    for (generated.expected) |expected| {
        app.sample();
        app.render();
        try std.testing.expectEqualSlices(i8, &expected, &app.logits);
        var predicted: u8 = 0;
        for (expected, 0..) |value, i| if (value > expected[predicted]) {
            predicted = @intCast(i);
        };
        try std.testing.expectEqual(@as(?u8, predicted), app.prediction);
        const distribution = scores.analyze(&expected);
        var surface = try m.surface.Mono1.init(&app.pixels, width, height);
        for (expected, 0..) |value, i| {
            const fill = scores.barWidth(value, distribution.min, distribution.max, 78);
            changed = changed or fill != previous_widths[i];
            previous_widths[i] = fill;
            for (0..78) |x| for (0..5) |y| {
                try std.testing.expectEqual(x < fill, surface.get(377 + @as(i16, @intCast(x)), 67 + @as(i16, @intCast(i)) * 14 + @as(i16, @intCast(y))));
            };
        }
    }
    try std.testing.expect(changed);
    app.clear();
    app.render();
    try std.testing.expect(app.prediction == null);
    try std.testing.expectEqualSlices(i8, &@as([10]i8, @splat(0)), &app.logits);
    // The real SAMPLE input path still wraps to the first fixture after sixteen.
    app.receive(.{ .pointer_down = .{ .x = 110, .y = 220 } });
    app.receive(.{ .pointer_up = .{ .x = 110, .y = 220 } });
    try std.testing.expectEqualSlices(i8, &generated.expected[0], &app.logits);
}
test "all tied logits draw empty bars and preserve the prediction outline" {
    var app: App = .{};
    app.logits = @splat(-20);
    app.prediction = 0;
    app.render();
    var surface = try m.surface.Mono1.init(&app.pixels, width, height);
    for (0..10) |i| for (0..78) |x| {
        try std.testing.expect(!surface.get(377 + @as(i16, @intCast(x)), 68 + @as(i16, @intCast(i)) * 14));
    };
    try std.testing.expect(surface.get(316, 64));
}

test "trace uses exact Dense outputs and modes preserve all sixteen samples" {
    var app: App = .{};
    for (generated.expected) |expected| {
        app.sample();
        var ordinary: [10]i8 = undefined;
        var ws: Model.Workspace = .{};
        Model.infer(&app.input, &ordinary, &ws);
        try std.testing.expectEqualSlices(i8, &ordinary, &app.logits);
        try std.testing.expectEqualSlices(i8, &expected, app.trace.layer(1));
        var hidden: [32]i8 = undefined;
        Model.Layer(0).run(&app.input, &hidden);
        try std.testing.expectEqualSlices(i8, &hidden, app.trace.layer(0));
        const pixels = app.canvas.pixels;
        const count = app.inference_count;
        const trace = app.trace;
        for ([_]inspector.Mode{ .network, .step, .play }) |mode| {
            app.inspection.mode = mode;
            app.inspection.stage = 3;
            app.render();
            try std.testing.expectEqualSlices(i8, &expected, &app.logits);
            try std.testing.expectEqualSlices(u8, &pixels, &app.canvas.pixels);
            try std.testing.expectEqualSlices(i8, &trace.values, &app.trace.values);
            try std.testing.expectEqual(count, app.inference_count);
        }
    }
    app.inspection.mode = .network;
    app.inspection.hidden = 31;
    app.sample();
    try std.testing.expectEqual(@as(u8, 0), app.inspection.stage);
    try std.testing.expectEqual(@as(usize, 31), app.inspection.hidden);
    app.clear();
    try std.testing.expectEqualSlices(i8, &@as([42]i8, @splat(0)), &app.trace.values);
    try std.testing.expect(app.prediction == null);
    try std.testing.expect(!app.inspection.running);
}

test "mode widgets, neuron hit testing and step controls use real input dispatch" {
    var app: App = .{};
    app.sample();
    app.render();
    const input = app.input;
    const logits = app.logits;
    app.receive(.{ .pointer_down = .{ .x = 365, .y = 18 } });
    app.receive(.{ .pointer_up = .{ .x = 365, .y = 18 } });
    try std.testing.expectEqual(inspector.Mode.network, app.inspection.mode);
    app.receive(.{ .pointer_down = inspector.hiddenPoint(17) });
    app.receive(.{ .pointer_up = inspector.hiddenPoint(17) });
    try std.testing.expectEqual(@as(usize, 17), app.inspection.hidden);
    app.receive(.{ .pointer_down = inspector.outputPoint(4) });
    app.receive(.{ .pointer_up = inspector.outputPoint(4) });
    try std.testing.expectEqual(@as(?usize, 4), app.inspection.output);
    app.receive(.{ .pointer_down = .{ .x = 420, .y = 18 } });
    app.receive(.{ .pointer_up = .{ .x = 420, .y = 18 } });
    try std.testing.expectEqual(inspector.Mode.step, app.inspection.mode);
    app.receive(.{ .pointer_down = .{ .x = 90, .y = 252 } });
    app.receive(.{ .pointer_up = .{ .x = 90, .y = 252 } });
    try std.testing.expectEqual(@as(u8, 1), app.inspection.stage);
    app.receive(.{ .pointer_down = .{ .x = 315, .y = 18 } });
    app.receive(.{ .pointer_up = .{ .x = 315, .y = 18 } });
    try std.testing.expectEqual(inspector.Mode.play, app.inspection.mode);
    try std.testing.expectEqualSlices(i8, &input, &app.input);
    try std.testing.expectEqualSlices(i8, &logits, &app.logits);
    try std.testing.expectEqual(@as(usize, 17), app.inspection.hidden);
}
test {
    _ = inspector;
}

test "PLAY pixels below navigator retain pre-inspector snapshot" {
    var app: App = .{};
    app.render();
    app.sample();
    app.render();
    var hash: u64 = 14695981039346656037;
    for (app.pixels[480 * 4 ..]) |b| hash = (hash ^ b) *% 1099511628211;
    try std.testing.expectEqual(@as(u64, 0xbe7698fae0a7df11), hash);
}

test "NETWORK framebuffer matches WebAssembly fixture bit for bit" {
    var app: App = .{};
    app.render();
    app.sample();
    app.render();
    app.receive(.{ .pointer_down = .{ .x = 365, .y = 18 } });
    app.receive(.{ .pointer_up = .{ .x = 365, .y = 18 } });
    var now: u32 = 0;
    while (now <= 2200) : (now += 16) _ = app.tick(now);
    try std.testing.expectEqual(@as(u8, 3), app.inspection.stage);
    var hash: u64 = 14695981039346656037;
    for (app.pixels) |b| hash = (hash ^ b) *% 1099511628211;
    try std.testing.expectEqual(@as(u64, 0x44d3f2fa2e1667f2), hash);
    try std.testing.expectEqual(@as(usize, 1), app.inference_count);
}

test "parameter inspection reconstructs every hidden activation from real weights" {
    const L = Model.Layer(0);
    const q = L.quantization;
    var app: App = .{};
    for (generated.inputs) |input| {
        app.sample();
        for (0..32) |row| {
            var acc: i64 = L.biasAt(row);
            for (input, 0..) |v, i| acc += (@as(i64, v) - q.input_zero) * L.weightAt(row, i);
            const product = acc * q.multiplier;
            const divisor = @as(u64, 1) << q.shift;
            const rounded: i64 = @intCast((@abs(product) + divisor / 2) / divisor);
            const raw = (if (product < 0) -rounded else rounded) + q.output_zero;
            const expected: i8 = @intCast(@max(q.output_zero, @max(-128, @min(127, raw))));
            try std.testing.expectEqual(expected, app.trace.layer(0)[row]);
        }
    }
}
