//! Synchronous borrowed events -> pure measurement -> bounded stderr rendering.
const std = @import("std");
pub const Mode = enum { auto, plain, off };
pub const Kind = enum { started, updated, epoch, completed, failed };
pub const Metric = struct { name: []const u8, value: f64 };
pub const Event = struct { name: []const u8, kind: Kind = .updated, done: u64 = 0, total: ?u64 = null, metrics: []const Metric = &.{}, detail: []const u8 = "", unit: []const u8 = "items" };
/// Callback must consume borrowed names/metrics synchronously; must not mutate training.
pub const Observer = struct {
    context: ?*anyopaque = null,
    callback: ?*const fn (?*anyopaque, Event) void = null,
    pub fn emit(self: Observer, event: Event) void {
        if (self.callback) |f| f(self.context, event);
    }
    pub fn task(self: Observer, name: []const u8, total: ?u64) Task {
        self.emit(.{ .name = name, .kind = .started, .total = total });
        return .{ .observer = self, .name = name, .total = total };
    }
};
pub const Task = struct {
    observer: Observer,
    name: []const u8,
    total: ?u64,
    done: u64 = 0,
    terminal: bool = false,
    unit: []const u8 = "items",
    pub fn update(self: *Task, done: u64, metrics: []const Metric) void {
        if (self.terminal) return;
        self.done = done;
        self.observer.emit(.{ .name = self.name, .done = done, .total = self.total, .metrics = metrics, .unit = self.unit });
    }
    pub fn finish(self: *Task) void {
        self.finishWithMetrics(&.{});
    }
    pub fn finishWithMetrics(self: *Task, metrics: []const Metric) void {
        if (self.terminal) return;
        self.terminal = true;
        if (self.total) |total| self.done = total;
        self.observer.emit(.{ .name = self.name, .kind = .completed, .done = self.done, .total = self.total, .unit = self.unit, .metrics = metrics });
    }
    pub fn fail(self: *Task, detail: []const u8) void {
        if (self.terminal) return;
        self.terminal = true;
        self.observer.emit(.{ .name = self.name, .kind = .failed, .done = self.done, .total = self.total, .detail = detail, .unit = self.unit });
    }
};
pub const Stats = struct { elapsed_ns: u64, fraction: ?f64, rate: ?f64, eta_seconds: ?f64 };
pub fn measure(event: Event, start_ns: u64, now_ns: u64) Stats {
    const elapsed = now_ns -| start_ns;
    const rate: ?f64 = if (elapsed == 0 or event.done == 0) null else @as(f64, @floatFromInt(event.done)) * 1e9 / @as(f64, @floatFromInt(elapsed));
    return .{ .elapsed_ns = elapsed, .fraction = if (event.total) |t| (if (t == 0) (if (event.kind == .completed) @as(f64, 1) else @as(f64, 0)) else @min(1, @as(f64, @floatFromInt(event.done)) / @as(f64, @floatFromInt(t)))) else null, .rate = rate, .eta_seconds = if (event.total) |t| (if (rate) |r| @as(f64, @floatFromInt(t -| event.done)) / r else if (event.kind == .completed) @as(f64, 0) else null) else null };
}
pub const Gate = struct {
    last_ns: ?u64 = null,
    pub fn allow(self: *Gate, now: u64, interval: u64, force: bool) bool {
        if (!force and self.last_ns != null and now -| self.last_ns.? < interval) return false;
        self.last_ns = now;
        return true;
    }
};
pub fn nowNs(io: std.Io) u64 {
    return @intCast(@max(0, @min(std.math.maxInt(u64), std.Io.Clock.awake.now(io).nanoseconds)));
}
fn fitLine(line: []u8, width: usize) []u8 {
    if (line.len <= width) return line;
    if (width < 4) return line[0..width];
    const limit = width - 3;
    const end = std.mem.lastIndexOfScalar(u8, line[0..limit], ' ') orelse limit;
    @memcpy(line[end..][0..3], "...");
    return line[0 .. end + 3];
}
pub const Cli = struct { args: []const []const u8, mode: Mode };
/// Remove only progress flags; leave existing positional CLI arguments unchanged.
pub fn cli(init: std.process.Init) !Cli {
    const raw = try init.minimal.args.toSlice(init.arena.allocator());
    var args: std.ArrayList([]const u8) = .empty;
    var mode = std.meta.stringToEnum(Mode, init.environ_map.get("ZINN_PROGRESS") orelse "auto") orelse return error.InvalidProgressMode;
    var quiet = false;
    for (raw) |arg| {
        if (std.mem.eql(u8, arg, "--quiet")) {
            quiet = true;
            continue;
        }
        if (std.mem.startsWith(u8, arg, "--progress=")) {
            mode = std.meta.stringToEnum(Mode, arg[11..]) orelse return error.InvalidProgressMode;
            continue;
        }
        try args.append(init.arena.allocator(), arg);
    }
    return .{ .args = try args.toOwnedSlice(init.arena.allocator()), .mode = if (quiet) .off else mode };
}
pub const Renderer = struct {
    const Slot = struct { name: [64]u8 = undefined, len: usize = 0, start_ns: u64 = 0, gate: Gate = .{}, log_gate: Gate = .{}, node: std.Progress.Node = .none };
    io: std.Io,
    mode: Mode,
    tty: bool = false,
    width: usize = 78,
    slots: [8]Slot = @splat(.{}),
    next_slot: usize = 0,
    root: std.Progress.Node = .none,
    active: bool = false,
    output_failed: bool = false,
    fn columns(io: std.Io, fallback: usize) usize {
        if (@import("builtin").os.tag == .windows) return @max(1, @min(160, fallback));
        var size: std.posix.winsize = .{ .row = 0, .col = 0, .xpixel = 0, .ypixel = 0 };
        const result = io.operate(.{ .device_io_control = .{ .file = .stderr(), .code = std.posix.T.IOCGWINSZ, .arg = &size } }) catch return @max(1, @min(160, fallback));
        const actual = if (result.device_io_control >= 0 and size.col > 1) size.col - 1 else fallback;
        return @max(1, @min(160, @min(actual, fallback)));
    }
    pub fn init(init_process: std.process.Init, mode: Mode) Renderer {
        const env = init_process.environ_map;
        const detected_tty = mode == .auto and env.get("CI") == null and !std.mem.eql(u8, env.get("TERM") orelse "dumb", "dumb") and (std.Io.File.stderr().isTty(init_process.io) catch false);
        const width = std.fmt.parseInt(usize, env.get("COLUMNS") orelse "78", 10) catch 78;
        const actual_width = if (detected_tty) columns(init_process.io, width) else @max(1, @min(160, width));
        const tty = detected_tty and actual_width >= 60; // Narrow displays safely use ordinary lines.
        const root = if (mode == .auto and env.get("ZIG_PROGRESS") != null and env.get("CI") == null) std.Progress.start(init_process.io, .{ .disable_printing = true, .root_name = "Zinn" }) else std.Progress.Node.none;
        // When a parent owns the terminal, publish IPC instead of drawing a
        // second carriage-return UI over its progress display.
        return .{ .io = init_process.io, .mode = mode, .tty = tty and root.index == .none, .width = actual_width, .root = root };
    }
    pub fn observer(self: *Renderer) Observer {
        return if (self.mode == .off) .{} else .{ .context = self, .callback = notify };
    }
    fn notify(context: ?*anyopaque, event: Event) void {
        const self: *Renderer = @ptrCast(@alignCast(context.?));
        if (self.output_failed) return;
        const now = nowNs(self.io);
        const key = event.name[0..@min(64, event.name.len)];
        var chosen: ?usize = null;
        for (&self.slots, 0..) |*slot, i| if (slot.len == key.len and std.mem.eql(u8, slot.name[0..slot.len], key)) {
            chosen = i;
            break;
        };
        const index = chosen orelse blk: {
            const i = self.next_slot;
            self.next_slot = (i + 1) % self.slots.len;
            break :blk i;
        };
        const slot = &self.slots[index];
        if (chosen == null or event.kind == .started) {
            slot.node.end();
            slot.* = .{ .start_ns = now };
            @memcpy(slot.name[0..key.len], key);
            slot.len = key.len;
            slot.node = self.root.start(event.name, if (event.total) |t| @intCast(@min(t, std.math.maxInt(usize))) else 0);
        }
        var epoch: f64 = 0;
        var epochs: f64 = 0;
        for (event.metrics) |m| {
            if (std.mem.eql(u8, m.name, "epoch")) epoch = m.value;
            if (std.mem.eql(u8, m.name, "epochs")) epochs = m.value;
        }
        const force = event.kind == .started or event.kind == .completed or event.kind == .failed or (event.kind == .epoch and (epoch == 1 or epoch == epochs));
        if (!slot.gate.allow(now, if (self.tty or self.root.index != .none) 200_000_000 else 5_000_000_000, force)) return;
        slot.node.setEstimatedTotalItems(if (event.total) |t| @intCast(@min(t, std.math.maxInt(usize))) else 0);
        slot.node.setCompletedItems(@intCast(@min(event.done, std.math.maxInt(usize))));
        if (event.kind == .completed or event.kind == .failed) {
            slot.node.end();
            slot.node = .none;
        }
        if (!slot.log_gate.allow(now, if (self.tty) 200_000_000 else 5_000_000_000, force)) return;
        const stats = measure(event, slot.start_ns, now);
        const inplace = self.tty and (event.kind == .started or event.kind == .updated);
        var bytes: [2048]u8 = undefined;
        var out: std.Io.Writer = .fixed(&bytes);
        out.print("{s} {s} ", .{ @tagName(event.kind), if (inplace) event.name[0..@min(20, event.name.len)] else event.name }) catch return;
        if (event.total) |t| {
            if (inplace) {
                out.writeAll("[") catch return;
                for (0..10) |i| out.writeByte(if (@as(f64, @floatFromInt(i)) < stats.fraction.? * 10) '#' else '-') catch return;
                out.writeAll("] ") catch return;
            }
            out.print("{d:.0}% {d}/{d} ", .{ 100 * stats.fraction.?, event.done, t }) catch return;
        } else out.print("{d}/? ", .{event.done}) catch return;
        out.print("elapsed={d:.1}s ", .{@as(f64, @floatFromInt(stats.elapsed_ns)) / 1e9}) catch return;
        if (stats.eta_seconds) |eta| out.print("eta={d:.1}s ", .{eta}) catch return else out.writeAll("eta=? ") catch return;
        if (stats.rate) |rate| out.print("rate={d:.1}{s}/s ", .{ rate, event.unit }) catch return;
        for (event.metrics) |metric| {
            if (std.math.isFinite(metric.value) and @floor(metric.value) == metric.value) out.print("{s}={d:.0} ", .{ metric.name, metric.value }) catch break else out.print("{s}={d:.5} ", .{ metric.name, metric.value }) catch break;
        }
        if (event.detail.len > 0) out.print("{s}", .{event.detail}) catch {};
        var line = out.buffered();
        // Do not emit escapes, control bytes or UTF-8; messages remain ASCII.
        for (line) |*c| if (c.* < 32 or c.* > 126) {
            c.* = '?';
        };
        if (self.active and !inplace) std.Io.File.stderr().writeStreamingAll(self.io, "\n") catch {};
        if (inplace) {
            line = fitLine(line, self.width);
            std.Io.File.stderr().writeStreamingAll(self.io, "\r") catch {
                self.output_failed = true;
                return;
            };
        }
        std.Io.File.stderr().writeStreamingAll(self.io, line) catch {
            self.output_failed = true;
            return;
        };
        if (inplace) {
            var padding: [160]u8 = @splat(' ');
            std.Io.File.stderr().writeStreamingAll(self.io, padding[0 .. self.width - line.len]) catch {};
        }
        self.active = inplace and event.kind != .completed and event.kind != .failed;
        if (!self.active) std.Io.File.stderr().writeStreamingAll(self.io, "\n") catch {};
    }
    /// On ordinary error unwinding, finish an in-place line. SIGINT may terminate
    /// without defers; no cursor/colour/terminal mode was changed to restore.
    pub fn deinit(self: *Renderer) void {
        for (&self.slots) |*slot| slot.node.end();
        self.root.end();
        if (self.active) std.Io.File.stderr().writeStreamingAll(self.io, "\n") catch {};
    }
};
test "zero, unknown totals, completion, rates, ETA and throttle" {
    const t = std.testing;
    try t.expectEqual(@as(?f64, null), measure(.{ .name = "x" }, 0, 1).fraction);
    try t.expectEqual(@as(?f64, 0), measure(.{ .name = "x", .total = 0 }, 0, 0).fraction);
    try t.expectEqual(@as(?f64, 1), measure(.{ .name = "x", .total = 0, .kind = .completed }, 0, 1).fraction);
    const s = measure(.{ .name = "x", .done = 10, .total = 20 }, 0, 2_000_000_000);
    try t.expectEqual(@as(?f64, 5), s.rate);
    try t.expectEqual(@as(?f64, 2), s.eta_seconds);
    try t.expectEqual(@as(?f64, 1), measure(.{ .name = "x", .done = 20, .total = 20 }, 0, 2).fraction);
    var g: Gate = .{};
    try t.expect(g.allow(0, 10, false));
    try t.expect(!g.allow(9, 10, false));
    try t.expect(g.allow(10, 10, false));
    try t.expect(g.allow(11, 10, true));
}
test "off means no callback; terminal tasks report failure once" {
    var off: Renderer = .{ .io = std.testing.io, .mode = .off };
    try std.testing.expect(off.observer().callback == null);
    const Capture = struct {
        failures: usize = 0,
        fn notify(ctx: ?*anyopaque, e: Event) void {
            const self: *@This() = @ptrCast(@alignCast(ctx.?));
            if (e.kind == .failed) self.failures += 1;
        }
    };
    var capture: Capture = .{};
    var task = (Observer{ .context = &capture, .callback = Capture.notify }).task("stage", null);
    task.fail("test error");
    task.fail("duplicate");
    task.finish();
    try std.testing.expectEqual(@as(usize, 1), capture.failures);
    var success = (Observer{ .context = &capture, .callback = Capture.notify }).task("stage", 0);
    success.finish();
    success.fail("unwound later");
    try std.testing.expectEqual(@as(usize, 1), capture.failures);
}
test "clipping never displays a partial ETA as a different number" {
    var text = "run 50% eta=123.4s rate=12.5/s".*;
    const clipped = fitLine(&text, 17);
    try std.testing.expectEqualStrings("run 50%...", clipped);
}
