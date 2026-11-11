//! Presentation only. Quantized parameters come from Dense; snapshots from Sequential.
const std = @import("std");
const m = @import("mimoc_ui");
const generated = @import("trained_model");
const Model = generated.Model;
const Hidden = Model.Layer(0);
const Output = Model.Layer(1);
const Ui = m.ui.Ui(u16, m.profiles.desktop);
pub const Mode = enum { play, network, step };
pub const State = struct {
    mode: Mode = .play,
    hidden: usize = 0,
    output: ?usize = null,
    pixel: usize = 0,
    stage: u8 = 0,
    running: bool = true,
    elapsed: u32 = 0,
    last_tick: ?u32 = null,
    pub fn restart(self: *State) void {
        self.stage = 0;
        self.elapsed = 0;
        self.last_tick = null;
        self.running = true;
    }
    pub fn clear(self: *State) void {
        const mode = self.mode;
        self.* = .{ .mode = mode, .running = false };
    }
    pub fn tick(self: *State, now: u32, valid: bool) bool {
        if (self.mode == .play or !valid or !self.running or self.stage == 3) {
            self.last_tick = null;
            return false;
        }
        const previous = self.last_tick orelse {
            self.last_tick = now;
            return false;
        };
        self.last_tick = now;
        // Focus suspension does not skip the entire explanation.
        self.elapsed += @min(now -% previous, 100);
        if (self.elapsed >= 650) {
            self.elapsed -= 650;
            self.stage += 1;
        }
        return true;
    }
    pub fn control(self: *State, target: u16) void {
        if (target == Ui.childId(Ui.rootId(1), 30)) {
            self.running = false;
            self.stage -|= 1;
        }
        if (target == Ui.childId(Ui.rootId(1), 31)) {
            self.running = false;
            self.stage = @min(3, self.stage + 1);
        }
        if (target == Ui.childId(Ui.rootId(1), 32)) {
            self.running = true;
            self.last_tick = null;
        }
        if (target == Ui.childId(Ui.rootId(1), 33)) self.running = false;
        if (target == Ui.childId(Ui.rootId(1), 34)) self.restart();
    }
    pub fn select(self: *State, p: m.geometry.Point) void {
        for (0..32) |i| {
            const n = hiddenPoint(i);
            if (@abs(@as(i32, p.x) - n.x) <= 5 and @abs(@as(i32, p.y) - n.y) <= 5) {
                self.hidden = i;
                self.output = null;
            }
        }
        for (0..10) |i| {
            const n = outputPoint(i);
            if (@abs(@as(i32, p.x) - n.x) <= 7 and @abs(@as(i32, p.y) - n.y) <= 6) self.output = i;
        }
        if (p.x >= 24 and p.x < 88 and p.y >= 146 and p.y < 210)
            self.pixel = @as(usize, @intCast(@divTrunc(p.y - 146, 4))) * 16 + @as(usize, @intCast(@divTrunc(p.x - 24, 4)));
    }
};
pub fn navigator(ui: *Ui) void {
    inline for (.{ "PLAY", "NETWORK", "STEP" }, 0..) |caption, i| {
        ui.buttonWith(20 + i, caption, .{ .offset = .{ .x = 292 + @as(i16, @intCast(i)) * 56, .y = 12 }, .size = .{ .w = 52, .h = 16 }, .text_alignment = .center, .text_vertical_alignment = .center });
    }
}
pub fn hiddenPoint(i: usize) m.geometry.Point {
    return .{ .x = 156 + @as(i16, @intCast(i % 4)) * 23, .y = 62 + @as(i16, @intCast(i / 4)) * 17 };
}
pub fn outputPoint(i: usize) m.geometry.Point {
    return .{ .x = 342, .y = 61 + @as(i16, @intCast(i)) * 14 };
}
/// ReLU zero point maps to black. 127 maps to full brightness, never a probability.
pub fn intensity(value: i8) u8 {
    const amount: i32 = @max(0, @as(i32, value) - Hidden.output_zero);
    return @intCast(@divTrunc(amount * 255, 127 - Hidden.output_zero));
}
/// Two strongest absolute weights per output; ties use the lower hidden index.
pub fn strong(output: usize, hidden: usize) bool {
    const magnitude = @abs(@as(i16, Output.weightAt(output, hidden)));
    var rank: usize = 0;
    for (0..32) |i| {
        const other = @abs(@as(i16, Output.weightAt(output, i)));
        if (other > magnitude or (other == magnitude and i < hidden)) rank += 1;
    }
    return rank < 2;
}
fn pattern(value: u8, x: usize, y: usize) bool {
    const bayer = [4][4]u8{ .{ 0, 8, 2, 10 }, .{ 12, 4, 14, 6 }, .{ 3, 11, 1, 9 }, .{ 15, 7, 13, 5 } };
    return value > @as(u16, bayer[y % 4][x % 4]) * 16 + 7;
}
const Signed = struct {
    value: i64,
    pub fn format(self: Signed, writer: *std.Io.Writer) std.Io.Writer.Error!void {
        if (self.value < 0) try writer.writeByte('-');
        try writer.print("{d}", .{@abs(self.value)});
    }
};
fn num(value: anytype) Signed {
    return .{ .value = value };
}
fn label(r: *m.mono1.Renderer, x: i16, y: i16, comptime fmt: []const u8, args: anytype) void {
    var buf: [100]u8 = undefined;
    const text = std.fmt.bufPrint(&buf, fmt, args) catch unreachable;
    m.font.draw(r, .tiny5x7, x, y, text, true);
}
fn connection(r: *m.mono1.Renderer, a: m.geometry.Point, b: m.geometry.Point, weight: i8, activation: i8, focused: bool, pulse: u32) void {
    // Solid positive; dashed negative. Strength controls deterministic stippling.
    const steps: i32 = @intCast(@max(@abs(@as(i32, b.x) - a.x), @abs(@as(i32, b.y) - a.y)));
    const strength = @abs(@as(i16, weight));
    var i: i32 = 0;
    while (i <= steps) : (i += 1) {
        if (weight == 0 or (weight < 0 and @mod(i, 6) >= 3)) continue;
        if (!focused and (activation <= Hidden.output_zero or (strength < 32 and @mod(i, 3) != 0))) continue;
        r.pixel(@intCast(a.x + @divTrunc((@as(i32, b.x) - a.x) * i, steps)), @intCast(a.y + @divTrunc((@as(i32, b.y) - a.y) * i, steps)), true);
    }
    if (activation > Hidden.output_zero and weight != 0 and pulse > 0) {
        const t: i32 = @intCast(@min(650, pulse));
        r.fillRect(.{ .x = @intCast(a.x + @divTrunc((@as(i32, b.x) - a.x) * t, 650) - 1), .y = @intCast(a.y + @divTrunc((@as(i32, b.y) - a.y) * t, 650) - 1), .w = 3, .h = 3 }, true);
    }
}
pub fn render(app: anytype) void {
    const state = &app.inspection;
    const valid = app.prediction != null;
    app.display.viewport = .{ .w = 480, .h = 272 };
    var ui = Ui.begin(&app.display);
    var root = ui.stack(1, .{});
    ui.textWith(2, "ZINN / NETWORK INSPECTOR", .{ .offset = .{ .x = 24, .y = 16 } });
    navigator(&ui);
    inline for (.{ "PREV", "NEXT", "PLAY", "PAUSE", "REPLAY" }, 0..) |text, i| {
        ui.buttonWith(30 + i, text, .{ .offset = .{ .x = 24 + @as(i16, @intCast(i)) * 54, .y = 244 }, .size = .{ .w = 50, .h = 18 }, .text_alignment = .center, .text_vertical_alignment = .center });
    }
    ui.buttonWith(10, "CLEAR", .{ .offset = .{ .x = 348, .y = 244 }, .size = .{ .w = 50, .h = 18 }, .text_alignment = .center, .text_vertical_alignment = .center });
    ui.buttonWith(11, "SAMPLE", .{ .offset = .{ .x = 402, .y = 244 }, .size = .{ .w = 54, .h = 18 }, .text_alignment = .center, .text_vertical_alignment = .center });
    root.end();
    ui.finish();
    m.headless.render(&app.display, &app.pixels, 480, 272) catch unreachable;
    var surface = m.surface.Mono1.init(&app.pixels, 480, 272) catch unreachable;
    var r = m.mono1.Renderer.init(&surface);
    r.hline(24, 32, 432, true);
    r.hline(292 + @as(i16, @intCast(@backingInt(state.mode))) * 56, 30, 52, true);
    label(&r, 24, 42, "INPUT 256", .{});
    label(&r, 142, 42, "HIDDEN 32", .{});
    label(&r, 328, 42, "OUTPUT 10", .{});
    const stage: u8 = if (valid) state.stage else 0;
    const hidden = app.trace.layer(0);
    // At most 30 standard/hidden-focused or 32 output-focused edges.
    if (stage >= 1) for (0..10) |o| {
        for (0..32) |h| {
            const focus = if (state.output) |selected| selected == o else state.hidden == h;
            if (if (state.output) |selected| selected != o else (!focus and !strong(o, h))) continue;
            connection(&r, hiddenPoint(h), outputPoint(o), Output.weightAt(o, h), hidden[h], focus, if (stage == 1) state.elapsed else 0);
        }
    };
    if (stage >= 1) if (state.output) |o| {
        var a = hiddenPoint(state.hidden);
        var b = outputPoint(o);
        a.y += 1;
        b.y += 1;
        connection(&r, a, b, Output.weightAt(o, state.hidden), hidden[state.hidden], true, 0);
    };
    for (0..64) |y| for (0..64) |x| {
        const q = app.input[(y / 4) * 16 + x / 4];
        const v: u8 = @intFromFloat(std.math.clamp(@as(f32, @floatFromInt(q)) * generated.input_scale * 255, 0, 255));
        if (valid and pattern(v, x, y)) r.pixel(24 + @as(i16, @intCast(x)), 60 + @as(i16, @intCast(y)), true);
        const w = Hidden.weightAt(state.hidden, (y / 4) * 16 + x / 4);
        const amount: u8 = @intCast(@min(255, @as(u16, @abs(@as(i16, w))) * 2));
        if (pattern(amount, x, y) and (w >= 0 or (x + y) % 2 == 0)) r.pixel(24 + @as(i16, @intCast(x)), 146 + @as(i16, @intCast(y)), true);
    };
    r.rect(.{ .x = 23, .y = 59, .w = 66, .h = 66 }, true);
    label(&r, 24, 132, "H{d} WEIGHTS", .{state.hidden});
    r.rect(.{ .x = 23, .y = 145, .w = 66, .h = 66 }, true);
    for (0..32) |h| {
        const p = hiddenPoint(h);
        // Erase crossing edges beneath nodes, then dither the actual activation.
        r.fillRect(.{ .x = p.x - 4, .y = p.y - 4, .w = 9, .h = 9 }, false);
        r.rect(.{ .x = p.x - 4, .y = p.y - 4, .w = 9, .h = 9 }, true);
        for (0..7) |y| for (0..7) |x| {
            if (stage >= 1 and pattern(intensity(hidden[h]), x, y)) r.pixel(p.x - 3 + @as(i16, @intCast(x)), p.y - 3 + @as(i16, @intCast(y)), true);
        };
        if (h == state.hidden) r.rect(.{ .x = p.x - 6, .y = p.y - 6, .w = 13, .h = 13 }, true);
    }
    for (0..10) |o| {
        const p = outputPoint(o);
        r.fillRect(.{ .x = p.x - 6, .y = p.y - 5, .w = 13, .h = 11 }, false);
        r.rect(.{ .x = p.x - 6, .y = p.y - 5, .w = 13, .h = 11 }, true);
        label(&r, p.x - 2, p.y - 3, "{d}", .{o});
        if (stage >= 2) label(&r, 362, p.y - 3, "{f}", .{num(app.logits[o])});
        if (state.output == o or (stage == 3 and app.prediction == @as(u8, @intCast(o)))) r.rect(.{ .x = p.x - 8, .y = p.y - 7, .w = 66, .h = 15 }, true);
    }
    const h = state.hidden;
    label(&r, 100, 216, "H{d} A:{f} Z:{f} S:{d:.4} B:{f}", .{ h, num(hidden[h]), num(Hidden.output_zero), Hidden.output_scale.?, num(Hidden.biasAt(h)) });
    if (state.output) |o| {
        label(&r, 24, 228, "H{d}/O{d} W:{f} B:{f} SOLID POS / DASH NEG", .{ h, o, num(Output.weightAt(o, h)), num(Output.biasAt(o)) });
    } else {
        const p = state.pixel;
        label(&r, 24, 228, "PIX {d}: IN:{f} W:{f} / BRIGHT:RELU ACTIVITY", .{ p, num(app.input[p]), num(Hidden.weightAt(h, p)) });
    }
    const explanations = [_][]const u8{
        "0 INPUT: HANDWRITING BECOMES 256 NUMBERS",
        "1 HIDDEN: WEIGHTED INPUTS AND BIAS THEN RELU",
        "2 OUTPUT: 32 ACTIVATIONS PRODUCE 10 LOGITS",
        "3 PREDICTION: CHOOSE THE LARGEST LOGIT",
    };
    m.font.draw(&r, .tiny5x7, 100, 202, if (valid) explanations[stage] else "USE SAMPLE OR DRAW IN PLAY MODE", true);
    if (stage == 0 and valid) {
        // Pedagogical aggregate flow: input pixels feed every hidden neuron.
        r.line(91, 91, 130, 91, true);
        if (state.elapsed > 0) r.fillRect(.{ .x = 91 + @as(i16, @intCast(state.elapsed * 39 / 650)), .y = 90, .w = 3, .h = 3 }, true);
    }
}
test "zero point brightness, deterministic strongest edges, selection and bounded stages" {
    try std.testing.expectEqual(@as(u8, 0), intensity(@intCast(Hidden.output_zero)));
    try std.testing.expectEqual(@as(u8, 255), intensity(127));
    for (0..10) |o| {
        var count: usize = 0;
        for (0..32) |h| {
            if (strong(o, h)) count += 1;
        }
        try std.testing.expectEqual(@as(usize, 2), count);
    }
    var s: State = .{};
    try std.testing.expectEqual(Mode.play, s.mode);
    s.mode = .step;
    s.select(hiddenPoint(31));
    try std.testing.expectEqual(@as(usize, 31), s.hidden);
    s.select(outputPoint(9));
    try std.testing.expectEqual(@as(?usize, 9), s.output);
    s.control(Ui.childId(Ui.rootId(1), 30));
    try std.testing.expectEqual(@as(u8, 0), s.stage);
    for (0..8) |_| s.control(Ui.childId(Ui.rootId(1), 31));
    try std.testing.expectEqual(@as(u8, 3), s.stage);
    s.restart();
    _ = s.tick(0, true);
    for (1..22) |i| _ = s.tick(@intCast(i * 100), true);
    try std.testing.expectEqual(@as(u8, 3), s.stage);
    try std.testing.expect(!s.tick(3000, true));
    s.clear();
    try std.testing.expectEqual(Mode.step, s.mode);
    try std.testing.expect(!s.running);
}
