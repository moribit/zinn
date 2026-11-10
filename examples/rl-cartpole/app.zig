const std = @import("std");
const m = @import("mimoc_ui");
const z = @import("zinn");
const a = @import("agent.zig");
const config = @import("options");
const Ui = m.ui.Ui(u16, .{ .desktop_input = true, .max_nodes = 64, .max_animations = 0, .diagnostics = true });
pub const width = 640;
pub const height = 400;
const Integer = @import("integer_policy");
const IM = Integer.Model;
const Watch = enum { live_float, saved_float, int8, compare };
pub const Mode = enum { train, watch };
pub const App = struct {
    storage: [config.replay_capacity]z.rl.Transition(4) = undefined,
    session: a.Session = undefined,
    initial: a.T = undefined,
    watch: a.env.Environment = .{},
    watch_integer: a.env.Environment = .{},
    integer_workspace: IM.Workspace = .{},
    integer_output: [IM.output_len]i8 = @splat(0),
    watch_kind: Watch = .live_float,
    watch_episode: u32 = 0,
    watch_action: usize = 0,
    mode: Mode = .train,
    paused: bool = false,
    speed_index: usize = 0,
    last_ms: ?u32 = null,
    accumulator: u64 = 0,
    error_name: []const u8 = "",
    chart: [120]u16 = @splat(0),
    display: Ui.Runtime = .{},
    pixels: [width * ((height + 7) / 8)]u8 = @splat(0),
    labels: [20][96]u8 = undefined,
    label_count: usize = 0,
    pub fn init(self: *App) !void {
        self.session = try a.Session.init(@import("train.zig").options(), &self.storage);
        self.initial = a.T.init(0);
        try self.initial.decode(@import("initial_policy").bytes);
        _ = self.watch.reset(0xd0000000);
        _ = self.watch_integer.reset(0xd0000000);
        self.watch_kind = .live_float;
        self.watch_episode = 0;
        self.watch_action = 0;
        self.mode = .train;
        self.paused = false;
        self.last_ms = null;
        self.accumulator = 0;
        self.error_name = "";
        @memset(&self.chart, 0);
        self.render();
    }
    pub fn control(self: *App, id: u16) !void {
        switch (id) {
            20 => {
                if (self.session.metrics.episodes >= self.session.options.episodes) try self.init();
                self.mode = .train;
                self.paused = false;
            },
            21 => self.paused = !self.paused,
            22 => try self.init(),
            23, 25, 26, 27 => {
                self.watch_kind = switch (id) {
                    25 => .saved_float,
                    26 => .int8,
                    27 => .compare,
                    else => .live_float,
                };
                self.mode = .watch;
                self.paused = false;
                _ = self.watch.reset(0xd0000000);
                _ = self.watch_integer.reset(0xd0000000);
                self.watch_episode = 0;
            },
            24 => self.speed_index = (self.speed_index + 1) % 3,
            else => {},
        }
        self.accumulator = 0;
    }
    fn policy(self: *const App) *const a.T {
        return if (self.watch_kind != .live_float) &self.initial else if (self.session.metrics.best_episode > 0) &self.session.best else &self.initial;
    }
    pub fn advance(self: *App, steps: usize) !void {
        if (self.paused) return;
        for (0..steps) |_| switch (self.mode) {
            .train => {
                if (self.session.metrics.episodes >= self.session.options.episodes) {
                    self.paused = true;
                    break;
                }
                if (try self.session.step()) |metrics| self.chart[(metrics.episodes - 1) % 120] = @intCast(metrics.reward);
            },
            .watch => {
                const use_integer = self.watch_kind == .int8 or self.watch_kind == .compare;
                if (self.watch.done and (!use_integer or self.watch_integer.done)) {
                    self.watch_episode += 1;
                    _ = self.watch.reset(0xd0000000 + self.watch_episode);
                    _ = self.watch_integer.reset(0xd0000000 + self.watch_episode);
                }
                if (!self.watch.done) {
                    const state = try self.watch.state.normalized();
                    const q = self.policy().predict(&state);
                    self.watch_action = try z.rl.dqn.greedy(&q);
                    _ = try self.watch.step(if (self.watch_action == 0) .left else .right);
                }
                if (use_integer and !self.watch_integer.done) {
                    const state = try self.watch_integer.state.normalized();
                    var encoded: [4]i8 = undefined;
                    for (&encoded, state) |*v, f| v.* = try z.export_model.quantizeInput(f, Integer.input_scale);
                    IM.infer(&encoded, &self.integer_output, &self.integer_workspace);
                    const selected = if (IM.output_len == 1) self.integer_output[0] > 0 else self.integer_output[1] > self.integer_output[0];
                    _ = try self.watch_integer.step(if (selected) .right else .left);
                }
            },
        };
    }
    pub fn tick(self: *App, now: u32) void {
        const last = self.last_ms orelse {
            self.last_ms = now;
            return;
        };
        self.last_ms = now;
        if (self.paused) return;
        const speeds = [_]u64{ 1, 8, 64 };
        self.accumulator += @as(u64, @min(now -% last, 100)) * speeds[self.speed_index];
        const budget = @min(self.accumulator / 20, 128);
        self.accumulator -= budget * 20;
        self.advance(@intCast(budget)) catch |err| {
            self.error_name = @errorName(err);
            self.paused = true;
        };
    }
    pub fn receive(self: *App, event: m.input.InputEvent) void {
        const action = self.display.dispatch(event);
        if (action.activated) for (20..28) |id| if (action.target == Ui.childId(Ui.rootId(1), @intCast(id))) self.control(@intCast(id)) catch |err| {
            self.error_name = @errorName(err);
            self.paused = true;
        };
        self.render();
    }
    fn text(self: *App, comptime fmt: []const u8, args: anytype) []const u8 {
        const s = std.fmt.bufPrint(&self.labels[self.label_count], fmt, args) catch unreachable;
        self.label_count += 1;
        return s;
    }
    pub fn render(self: *App) void {
        self.label_count = 0;
        self.display.viewport = .{ .w = width, .h = height };
        const metrics = self.session.metrics;
        const world = if (self.mode == .train) &self.session.world else if (self.watch_kind == .int8) &self.watch_integer else &self.watch;
        const action = if (self.mode == .train) self.session.last_action else if (self.watch_kind == .int8) (if (IM.output_len == 1) @as(usize, @intFromBool(self.integer_output[0] > 0)) else @as(usize, @intFromBool(self.integer_output[1] > self.integer_output[0]))) else self.watch_action;
        const model = if (self.mode == .train) &self.session.agent.online else self.policy();
        const state = world.state.normalized() catch @as([4]f32, @splat(0));
        const q = model.predict(&state);
        var ui = Ui.begin(&self.display);
        var root = ui.stack(1, .{});
        ui.textWith(2, "ZINN RL LAB / CARTPOLE", .{ .offset = .{ .x = 20, .y = 16 } });
        ui.textWith(3, if (self.error_name.len > 0) self.error_name else if (self.paused) "PAUSED" else if (self.mode == .train) "DQN 4-16-16-2 / TRAIN" else switch (self.watch_kind) {
            .compare => "COMPARE / SAVED",
            .int8 => "INT8 / SAVED",
            .saved_float => "FLOAT / SAVED",
            .live_float => "WATCH / GREEDY",
        }, .{ .offset = .{ .x = 440, .y = 16 } });
        ui.textWith(4, self.text("EP {d} / STEP {d}", .{ if (self.mode == .train) @min(metrics.episodes + 1, self.session.options.episodes) else @as(usize, self.watch_episode) + 1, world.steps }), .{ .offset = .{ .x = 30, .y = 62 } });
        ui.textWith(5, if (action == 0) "LEFT" else "RIGHT", .{ .offset = .{ .x = 314, .y = 62 } });
        ui.textWith(6, self.text("EPISODES {d}/{d}", .{ metrics.episodes, self.session.options.episodes }), .{ .offset = .{ .x = 400, .y = 56 } });
        ui.textWith(7, self.text("REWARD {d}", .{world.steps}), .{ .offset = .{ .x = 400, .y = 76 } });
        ui.textWith(8, self.text("MEAN100 {d:.1}", .{metrics.mean100}), .{ .offset = .{ .x = 400, .y = 96 } });
        ui.textWith(9, self.text("DEV EVAL {d:.1}", .{metrics.evaluation}), .{ .offset = .{ .x = 400, .y = 116 } });
        ui.textWith(10, self.text("BEST DEV {d:.1}", .{metrics.best_evaluation}), .{ .offset = .{ .x = 400, .y = 136 } });
        ui.textWith(11, self.text("EPSILON {d:.3}", .{if (self.mode == .watch) @as(f32, 0) else z.rl.dqn.epsilon(self.session.agent.options, self.session.agent.steps)}), .{ .offset = .{ .x = 400, .y = 156 } });
        ui.textWith(12, self.text("TD MSE {d:.5}", .{self.session.agent.last_loss}), .{ .offset = .{ .x = 400, .y = 176 } });
        ui.textWith(13, if (self.mode == .train) "POLICY / ONLINE FLOAT32" else if (self.watch_kind == .int8) "POLICY / SAVED INTEGER" else if (self.watch_kind == .compare or self.watch_kind == .saved_float) "POLICY / SAVED FLOAT32" else if (metrics.best_episode > 0) "POLICY / CURRENT BEST FLOAT32" else "POLICY / SAVED FLOAT32", .{ .offset = .{ .x = 20, .y = 254 } });
        ui.textWith(14, self.text("LEFT Q {d:.3} / RIGHT Q {d:.3}", .{ q[0], q[1] }), .{ .offset = .{ .x = 20, .y = 274 } });
        ui.textWith(15, "LAST 120 TRAIN REWARDS / 0-500", .{ .offset = .{ .x = 400, .y = 284 } });
        const labels = [_][]const u8{ "TRAIN", if (self.paused) "RESUME" else "PAUSE", "RESET", "WATCH", self.text("SPEED {d}X", .{([_]u8{ 1, 8, 64 })[self.speed_index]}) };
        for (labels, 0..) |label, i| ui.buttonWith(@intCast(20 + i), label, .{ .offset = .{ .x = 20 + @as(i16, @intCast(i)) * 120, .y = 316 }, .size = .{ .w = 104, .h = 26 }, .text_alignment = .center, .text_vertical_alignment = .center });
        const selectors = [_][]const u8{ "FLOAT", "INT8", "COMPARE" };
        for (selectors, 0..) |label, i| ui.buttonWith(@intCast(25 + i), label, .{ .offset = .{ .x = 20 + @as(i16, @intCast(i)) * 120, .y = 356 }, .size = .{ .w = 104, .h = 26 }, .text_alignment = .center, .text_vertical_alignment = .center });
        if (self.mode == .watch and (self.watch_kind == .compare or self.watch_kind == .int8)) {
            ui.textWith(16, self.text("F {d} / I {d} STEPS", .{ self.watch.steps, self.watch_integer.steps }), .{ .offset = .{ .x = 30, .y = 84 } });
            const float_state = self.watch.state.normalized() catch @as([4]f32, @splat(0));
            const fq = self.initial.predict(&float_state);
            var encoded: [4]i8 = undefined;
            var probe: [IM.output_len]i8 = undefined;
            for (&encoded, float_state) |*v, f| v.* = z.export_model.quantizeInput(f, Integer.input_scale) catch 0;
            IM.infer(&encoded, &probe, &self.integer_workspace);
            const same = @as(usize, @intFromBool(fq[1] > fq[0])) == (if (IM.output_len == 1) @as(usize, @intFromBool(probe[0] > 0)) else @as(usize, @intFromBool(probe[1] > probe[0])));
            ui.textWith(17, if (same) "SAME-STATE ACTION: MATCH" else "SAME-STATE ACTION: MISMATCH", .{ .offset = .{ .x = 390, .y = 362 } });
            ui.textWith(19, "VIEWS: FLOAT / INT8", .{ .offset = .{ .x = 30, .y = 102 } });
            ui.textWith(18, self.text("INT {d} / F ANG {d:.3} / I ANG {d:.3}", .{ self.integer_output[0], self.watch.state.theta, self.watch_integer.state.theta }), .{ .offset = .{ .x = 20, .y = 298 } });
        }
        root.end();
        ui.finish();
        m.headless.render(&self.display, &self.pixels, width, height) catch unreachable;
        var surface = m.surface.Mono1.init(&self.pixels, width, height) catch unreachable;
        var r = m.mono1.Renderer.init(&surface);
        r.hline(20, 34, 600, true);
        r.rect(.{ .x = 20, .y = 52, .w = 360, .h = 184 }, true);
        if (self.mode == .watch and self.watch_kind == .compare) {
            cart(&r, self.watch.state, 110, 72);
            cart(&r, self.watch_integer.state, 290, 72);
            r.vline(200, 106, 116, true);
        } else cart(&r, world.state, 200, 150);
        r.rect(.{ .x = 400, .y = 206, .w = 220, .h = 70 }, true);
        const n = @min(metrics.episodes, 120);
        const first = metrics.episodes - n;
        var px: i16 = 401;
        var py: i16 = 274;
        for (0..n) |i| {
            const x: i16 = 402 + @divTrunc(@as(i16, @intCast(i)) * 216, 119);
            const y: i16 = @intCast(274 - @divTrunc(@as(i32, self.chart[(first + i) % 120]) * 66, 500));
            if (i > 0) r.line(px, py, x, y, true);
            px = x;
            py = y;
        }
    }
};

fn cart(r: *m.mono1.Renderer, state: a.env.State, center: i16, extent: f32) void {
    const cx: i16 = center + @as(i16, @intFromFloat(std.math.clamp(state.x / 2.4, -1, 1) * extent));
    const tx: i16 = cx + @as(i16, @intFromFloat(@sin(state.theta) * 82));
    const ty: i16 = 196 - @as(i16, @intFromFloat(@cos(state.theta) * 82));
    r.hline(center - @as(i16, @intFromFloat(extent)), 214, @as(i16, @intFromFloat(extent * 2)), true);
    r.fillRect(.{ .x = cx - 14, .y = 196, .w = 28, .h = 14 }, true);
    r.circle(cx - 8, 212, 3, true);
    r.circle(cx + 8, 212, 3, true);
    r.line(cx, 196, tx, ty, true);
    r.line(cx + 1, 196, tx + 1, ty, true);
    r.circle(tx, ty, 3, true);
}

test "pause/resume/watch/reset and scheduling chunks preserve training" {
    var app: App = .{};
    try app.init();
    try app.advance(1000);
    const original = app.session.agent.online.encode();
    try app.control(21);
    try app.advance(100);
    const paused = app.session.agent.online.encode();
    try std.testing.expectEqualSlices(u8, &original, &paused);
    try app.control(23);
    try app.advance(1000);
    const watched = app.session.agent.online.encode();
    try std.testing.expectEqualSlices(u8, &original, &watched);
    try app.control(20);
    try app.advance(100);
    const continued = app.session.agent.online.encode();
    var storage: [config.replay_capacity]z.rl.Transition(4) = undefined;
    var reference = try a.Session.init(@import("train.zig").options(), &storage);
    for (0..1100) |_| {
        _ = try reference.step();
    }
    const expected = reference.agent.online.encode();
    try std.testing.expectEqualSlices(u8, &expected, &continued);
    try app.control(22);
    try std.testing.expectEqual(@as(usize, 0), app.session.agent.steps);
    try std.testing.expectEqual(@as(usize, 0), app.session.agent.replay.count);
    for (0..100) |_| {
        try app.advance(10);
        app.render();
    }
    const reset = app.session.agent.online.encode();
    try std.testing.expectEqualSlices(u8, &original, &reset);
}

test "speed and tick batching preserve the same training prefix" {
    var app: App = .{};
    try app.init();
    app.tick(0);
    for (1..101) |i| app.tick(@intCast(i * 20));
    const slow = app.session.agent.online.encode();
    try app.control(22);
    app.speed_index = 1;
    app.tick(0);
    for (1..26) |i| app.tick(@intCast(i * 10));
    const fast = app.session.agent.online.encode();
    try std.testing.expectEqual(@as(usize, 100), app.session.agent.steps);
    try std.testing.expectEqualSlices(u8, &slow, &fast);
}

test "saved compare uses paired initial states and freezes completed trajectories" {
    var app: App = .{};
    try app.init();
    try app.advance(1000);
    const before = app.session.agent.online.encode();
    const rng = app.session.agent.rng.state;
    const steps = app.session.agent.steps;
    try app.control(27);
    try std.testing.expect(std.meta.eql(app.watch.state, app.watch_integer.state));
    try app.advance(100);
    const after = app.session.agent.online.encode();
    try std.testing.expectEqualSlices(u8, &before, &after);
    try std.testing.expectEqual(rng, app.session.agent.rng.state);
    try std.testing.expectEqual(steps, app.session.agent.steps);
    app.render();
    app.watch.done = true;
    app.watch_integer.done = false;
    const frozen = app.watch.state;
    try app.advance(1);
    try std.testing.expect(std.meta.eql(frozen, app.watch.state));
    try app.control(26);
    try app.advance(10);
    app.render();
}
