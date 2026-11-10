const std = @import("std");
const p = @import("progress.zig");
const terminal = @import("terminal.zig");
fn field(w: *std.Io.Writer, width: usize, comptime fmt: []const u8, args: anytype) !void {
    var buffer: [96]u8 = undefined;
    const text = try std.fmt.bufPrint(&buffer, fmt, args);
    if (w.end + text.len <= width) try w.writeAll(text);
}
pub const State = struct {
    epoch: f64 = 0,
    epochs: f64 = 0,
    batch: f64 = 0,
    batches: f64 = 0,
    loss: ?f64 = null,
    validation: ?f64 = null,
    best: ?f64 = null,
    start: u64 = 0,
    estimator: p.Estimator = .{},
    pub fn update(self: *State, e: p.Event, now: u64) void {
        if (e.kind == .started) self.* = .{ .start = now };
        _ = self.estimator.update(e, self.start, now);
        for (e.metrics) |m| {
            if (!std.math.isFinite(m.value)) continue;
            if (std.mem.eql(u8, m.name, "epoch")) self.epoch = m.value;
            if (std.mem.eql(u8, m.name, "epochs")) self.epochs = m.value;
            if (std.mem.eql(u8, m.name, "batch")) self.batch = m.value;
            if (std.mem.eql(u8, m.name, "batches")) self.batches = m.value;
            if (std.mem.eql(u8, m.name, "loss")) self.loss = m.value;
            if (std.mem.eql(u8, m.name, "val_acc")) {
                self.validation = m.value;
                self.best = @max(self.best orelse m.value, m.value);
            }
            if (std.mem.eql(u8, m.name, "best_val_acc")) self.best = m.value;
        }
        if (self.epochs == 0 and self.epoch > 0 and e.total != null) self.epochs = @floatFromInt(e.total.?);
        if (e.kind == .epoch and self.epochs > 0 and e.total != null) {
            self.batches = @as(f64, @floatFromInt(e.total.?)) / self.epochs;
            self.batch = self.batches;
        }
    }
    pub fn format(self: State, buffer: []u8, e: p.Event, now: u64, width: usize) ![]u8 {
        var w: std.Io.Writer = .fixed(buffer);
        var s = p.measure(e, self.start, now);
        if (s.eta_seconds != null) if (self.estimator.rate) |rate| {
            s.rate = rate;
            s.eta_seconds = @as(f64, @floatFromInt(e.total.? -| e.done)) / rate;
        };
        if (self.epochs > 0) try w.print("E{d:.0}/{d:.0} ", .{ self.epoch, self.epochs }) else try w.writeAll("training ");
        if (width >= 76 and self.batches > 0) try field(&w, width, "B{d:.0}/{d:.0} ", .{ self.batch, self.batches });
        try terminal.bar(&w, s.fraction, if (width >= 116) 20 else if (width >= 56) 10 else 5);
        if (s.fraction) |f| try w.print(" {d}%", .{p.percent(f)});
        if (self.loss) |loss| try field(&w, width, " L{d:.3}", .{loss});
        if (width >= 56) {
            if (self.validation) |v| try field(&w, width, " V{d:.1}%", .{v});
            if (self.best) |v| try field(&w, width, " Best{d:.1}%", .{v});
        }
        if (width >= 76) {
            if (s.eta_seconds) |eta| try field(&w, width, " ETA {d:.0}s", .{eta});
        }
        if (w.end <= width) return w.buffered();
        const end = std.mem.lastIndexOfScalar(u8, buffer[0..width], ' ') orelse width;
        return buffer[0..end];
    }
};
test "training widths and validation survives batch updates" {
    var s: State = .{};
    const e: p.Event = .{ .name = "model", .kind = .epoch, .done = 100, .total = 200, .metrics = &.{ .{ .name = "epoch", .value = 1 }, .{ .name = "epochs", .value = 2 }, .{ .name = "loss", .value = 0.123 }, .{ .name = "val_acc", .value = 95 } } };
    s.update(e, 1_000_000_000);
    s.update(.{ .name = "model", .metrics = &.{.{ .name = "loss", .value = 0.1 }} }, 2_000_000_000);
    try std.testing.expectEqual(@as(?f64, 95), s.best);
    var buffer: [512]u8 = undefined;
    inline for (.{ 40, 60, 80, 120 }) |width| {
        const line = try s.format(&buffer, e, 2_000_000_000, width);
        try std.testing.expect(line.len <= width);
        try std.testing.expect(std.mem.indexOf(u8, line, "[#") != null);
    }
    s.update(.{ .name = "new model", .kind = .started }, 3_000_000_000);
    try std.testing.expectEqual(@as(?f64, null), s.best);
}
