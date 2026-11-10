const std = @import("std");
fn number(value: std.json.Value) !f64 {
    return switch (value) {
        .float => |v| v,
        .integer => |v| @floatFromInt(v),
        else => error.InvalidMetric,
    };
}
pub fn main(init: std.process.Init) !void {
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    const bytes = try std.Io.Dir.cwd().readFileAlloc(init.io, args[1], init.arena.allocator(), .limited(1024 * 1024));
    const r = try std.json.parseFromSlice(std.json.Value, init.arena.allocator(), bytes, .{});
    std.debug.print("CartPole saved evaluation (no new training): {s}\n", .{args[1]});
    for ([_][]const u8{ "random", "float", "integer", "agreement" }) |key| {
        const value = r.value.object.get(key).?;
        if (value.object.get("mean")) |mean| {
            std.debug.print("{s}: mean={d:.2} max={d} successes={d}/50\n", .{ key, try number(mean), value.object.get("maximum").?.integer, value.object.get("successes").?.integer });
        } else {
            const encoded = try std.json.Stringify.valueAlloc(init.arena.allocator(), value, .{});
            std.debug.print("{s}: {s}\n", .{ key, encoded });
        }
    }
    if (args.len == 3 and std.mem.eql(u8, args[2], "--check-improvement")) {
        const random = try number(r.value.object.get("random").?.object.get("mean").?);
        const learned = try number(r.value.object.get("float").?.object.get("mean").?);
        const integer = try number(r.value.object.get("integer").?.object.get("mean").?);
        if (learned <= 2 * random or integer <= random) return error.PolicyDidNotImprove;
    }
}
