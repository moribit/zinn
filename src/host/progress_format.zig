//! Download-specific formatting: primary information first, no raw B/s or
//! generic timer/bar text competing with the filename.
const std = @import("std");
const p = @import("progress.zig");
fn metric(e: p.Event, key: []const u8) f64 {
    for (e.metrics) |m| if (std.mem.eql(u8, m.name, key)) return m.value;
    return 0;
}
fn scale(value: f64) struct { factor: f64, unit: []const u8 } {
    if (value >= 1024 * 1024 * 1024) return .{ .factor = 1024 * 1024 * 1024, .unit = "GiB" };
    if (value >= 1024 * 1024) return .{ .factor = 1024 * 1024, .unit = "MiB" };
    if (value >= 1024) return .{ .factor = 1024, .unit = "KiB" };
    return .{ .factor = 1, .unit = "B" };
}
pub fn amount(w: *std.Io.Writer, value: f64) !void {
    const unit = scale(value);
    if (unit.factor == 1) try w.print("{d:.0}B", .{value}) else try w.print("{d:.2}{s}", .{ value / unit.factor, unit.unit });
}
fn stats(w: *std.Io.Writer, e: p.Event, s: p.Stats, rate: bool, eta: bool) !void {
    const unit = scale(@floatFromInt(e.total orelse e.done));
    if (e.total) |total| {
        if (unit.factor == 1) try w.print("{d}/{d}B", .{ e.done, total }) else try w.print("{d:.2}/{d:.2}{s}", .{ @as(f64, @floatFromInt(e.done)) / unit.factor, @as(f64, @floatFromInt(total)) / unit.factor, unit.unit });
        try w.print(" {d}%", .{p.percent(s.fraction.?)});
    } else try amount(w, @floatFromInt(e.done));
    if (rate) if (s.rate) |r| {
        try w.writeByte(' ');
        try amount(w, r);
        try w.writeAll("/s");
    };
    if (eta and e.total != null) {
        if (s.eta_seconds) |seconds| try w.print(" ETA {d:.0}s", .{seconds});
    }
}
fn name(w: *std.Io.Writer, text: []const u8, width: usize) !void {
    if (text.len <= width) return w.writeAll(text);
    if (width < 5) return w.writeAll(text[0..width]);
    const first = (width - 3) / 2;
    try w.writeAll(text[0..first]);
    try w.writeAll("...");
    try w.writeAll(text[text.len - (width - 3 - first) ..]);
}
pub fn visual(buffer: []u8, e: p.Event, s: p.Stats, width: usize) ![]u8 {
    var w: std.Io.Writer = .fixed(buffer);
    try @import("terminal.zig").bar(&w, if (e.kind == .completed) @as(?f64, 1) else s.fraction, if (width >= 76) 16 else if (width >= 56) 10 else 5);
    try w.writeByte(' ');
    if (e.kind == .completed and e.total == null) try w.writeAll("done ");
    try stats(&w, e, s, width >= 56, width >= 76);
    return buffer[0..@min(w.end, width)];
}
pub fn format(buffer: []u8, e: p.Event, s: p.Stats, columns: usize) ![]u8 {
    var out: std.Io.Writer = .fixed(buffer);
    if (std.mem.eql(u8, e.unit, "files")) {
        if (e.kind == .updated) return buffer[0..0];
        if (e.kind == .started) {
            try out.print("MNIST: {d} files", .{e.total orelse 4});
            return out.buffered();
        }
        if (e.kind == .failed) {
            try out.print("MNIST download failed: {s}", .{e.detail});
            return out.buffered();
        }
        try p.summary.download(&out, e.done, e.total orelse e.done, metric(e, "downloaded"), metric(e, "cached"));
        if (out.end + 10 <= columns) try out.print(" ({d:.1}s)", .{@as(f64, @floatFromInt(s.elapsed_ns)) / 1e9});
        return out.buffered();
    }
    if (e.kind == .started) {
        const prefix = "download ";
        try out.writeAll(prefix);
        try name(&out, e.name, columns -| prefix.len);
        return out.buffered();
    }
    if (e.kind == .failed) {
        try out.print("failed {s}: {s}", .{ e.name, e.detail });
        return out.buffered();
    }
    if (std.mem.eql(u8, e.detail, "cached")) {
        try out.writeAll("cached ");
        try name(&out, e.name, columns -| "cached ".len);
        var size_buf: [48]u8 = undefined;
        var size: std.Io.Writer = .fixed(&size_buf);
        try amount(&size, @floatFromInt(e.done));
        if (out.end + 1 + size.end <= columns) try out.writeByte(' ') else try out.writeByte('\n');
        try out.writeAll(size.buffered());
        return out.buffered();
    }
    var detail_buf: [192]u8 = undefined;
    var detail: std.Io.Writer = .fixed(&detail_buf);
    try stats(&detail, e, s, true, true);
    // The complete filename and all five primary fields fit most 78/80-column
    // displays. On narrow displays keep filename and statistics on two lines.
    if (e.name.len + 1 + detail.end <= columns) {
        try out.writeAll(e.name);
        try out.writeByte(' ');
        try out.writeAll(detail.buffered());
        return out.buffered();
    }
    if (detail.end > columns) {
        detail.end = 0;
        try stats(&detail, e, s, true, false);
    }
    if (detail.end > columns) {
        detail.end = 0;
        try stats(&detail, e, s, false, false);
    }
    if (e.kind == .completed) {
        try name(&out, e.name, columns);
        try out.writeByte('\n');
    }
    try out.writeAll(detail.buffered());
    return out.buffered();
}
test "download layout preserves bytes, percentage, human speed and ETA at 40/80 columns" {
    const e: p.Event = .{ .name = "train-images-idx3-ubyte.gz", .done = 5 * 1024 * 1024, .total = 10 * 1024 * 1024, .unit = "B", .kind = .updated };
    const s = p.measure(e, 0, 1_000_000_000);
    var buffer: [1024]u8 = undefined;
    inline for (.{ 40, 60, 80 }) |width| {
        const line = try format(&buffer, e, s, width);
        try std.testing.expect(std.mem.indexOf(u8, line, "5.00/10.00MiB 50%") != null);
        try std.testing.expect(std.mem.indexOf(u8, line, "5.00MiB/s") != null);
        try std.testing.expect(std.mem.indexOf(u8, line, "ETA 1s") != null);
        var rows = std.mem.splitScalar(u8, line, '\n');
        while (rows.next()) |row| try std.testing.expect(row.len <= width);
    }
    try std.testing.expectEqualStrings("1.00KiB", blk: {
        var w: std.Io.Writer = .fixed(&buffer);
        try amount(&w, 1024);
        break :blk w.buffered();
    });
    const unknown = try format(&buffer, .{ .name = "file.gz", .unit = "B", .done = 1024 }, p.measure(.{ .name = "file.gz", .done = 1024 }, 0, 1_000_000_000), 80);
    try std.testing.expect(std.mem.indexOf(u8, unknown, "ETA") == null);
}
test "cached files and aggregate summaries fit narrow displays without fake rates" {
    var buffer: [512]u8 = undefined;
    const cached: p.Event = .{ .name = "train-images-idx3-ubyte.gz", .kind = .completed, .done = 9912422, .total = 9912422, .unit = "B", .detail = "cached" };
    const line = try format(&buffer, cached, p.measure(cached, 0, 1), 40);
    try std.testing.expectEqualStrings("cached train-images-idx3-ubyte.gz\n9.45MiB", line);
    const all: p.Event = .{ .name = "MNIST", .kind = .completed, .done = 4, .total = 4, .unit = "files", .metrics = &.{ .{ .name = "downloaded", .value = 1 }, .{ .name = "cached", .value = 3 } } };
    const summary = try format(&buffer, all, p.measure(all, 0, 1_000_000_000), 40);
    try std.testing.expectEqualStrings("completed MNIST 4/4: 1 new, 3 cached", summary);
    try std.testing.expectEqualStrings("", try format(&buffer, .{ .name = "MNIST", .unit = "files", .done = 1 }, p.measure(all, 0, 1), 40));
}
test "visual download fits physical terminal columns and drops whole optional fields" {
    const e: p.Event = .{ .name = "fixture.gz", .done = 5 * 1024 * 1024, .total = 10 * 1024 * 1024, .unit = "B" };
    var buffer: [512]u8 = undefined;
    inline for (.{ 39, 59, 79, 119 }) |width| {
        const line = try visual(&buffer, e, p.measure(e, 0, 1_000_000_000), width);
        try std.testing.expect(line.len <= width);
        try std.testing.expect(std.mem.indexOf(u8, line, "5.00/10.00MiB 50%") != null);
        try std.testing.expectEqual(width >= 56, std.mem.indexOf(u8, line, "5.00MiB/s") != null);
        try std.testing.expectEqual(width >= 76, std.mem.indexOf(u8, line, "ETA 1s") != null);
    }
    const unknown: p.Event = .{ .name = "file.gz", .done = 1024, .kind = .completed, .unit = "B" };
    const done = try visual(&buffer, unknown, p.measure(unknown, 0, 1_000_000_000), 39);
    try std.testing.expect(std.mem.indexOf(u8, done, "[#####] done 1.00KiB") != null);
    try std.testing.expect(std.mem.indexOf(u8, done, "%") == null);
}
