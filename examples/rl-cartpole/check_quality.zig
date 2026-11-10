//! Offline regression gate for the fixed seed-42 comparison.
const std = @import("std");
fn number(value: std.json.Value) !f64 {
    return switch (value) {
        .float => |v| v,
        .integer => |v| @floatFromInt(v),
        else => error.InvalidMetric,
    };
}
pub fn main(init: std.process.Init) !void {
    const allocator = init.arena.allocator();
    const args = try init.minimal.args.toSlice(allocator);
    if (args.len != 2) return error.ExpectedReport;
    const bytes = try std.Io.Dir.cwd().readFileAlloc(init.io, args[1], allocator, .limited(1024 * 1024));
    const doc = try std.json.parseFromSlice(std.json.Value, allocator, bytes, .{});
    const r = doc.value.object;
    const original = try number(r.get("float").?.object.get("mean").?);
    const baseline = try number(r.get("baseline").?.object.get("mean").?);
    const improved = try number(r.get("improved").?.object.get("mean").?);
    if (improved < baseline or improved < 0.85 * original) return error.ControlQualityRegression;
    const analyses = r.get("analyses").?.array.items;
    for (analyses) |analysis| {
        const counts = analysis.object;
        if (counts.get("count").?.integer <= 0 or counts.get("mismatches").?.integer > counts.get("count").?.integer) return error.InvalidDiagnostics;
    }
}
