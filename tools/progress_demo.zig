const std = @import("std");
const p = @import("zinn").host.progress;
pub fn main(init: std.process.Init) !void {
    const parsed = try p.cli(init);
    var renderer = p.Renderer.init(init, parsed.mode);
    defer renderer.deinit();
    var download = false;
    var fail = false;
    var wait = false;
    for (parsed.args[1..]) |arg| {
        if (std.mem.eql(u8, arg, "--download")) download = true;
        if (std.mem.eql(u8, arg, "--fail")) fail = true;
        if (std.mem.eql(u8, arg, "--wait")) wait = true;
    }
    var task: p.Task = .{ .observer = renderer.observer(), .name = if (download) "fixture.gz" else "Fixture", .total = 10000, .unit = if (download) "B" else "items" };
    renderer.observer().emit(.{ .name = task.name, .kind = .started, .total = task.total, .unit = task.unit, .detail = if (download) "1/1" else "" });
    errdefer task.fail("fixture failure");
    for (0..10000) |i| {
        task.update(i + 1, &.{.{ .name = "loss", .value = 0.125 }});
        if (fail and i == 5000) return error.FixtureFailure;
        if (wait and (!download or i % 500 == 0)) try std.Io.sleep(init.io, .fromMilliseconds(if (download) 250 else 10), .awake);
    }
    task.finish();
    try std.Io.File.stdout().writeStreamingAll(init.io, "{\"fixture\":true}\n");
}
