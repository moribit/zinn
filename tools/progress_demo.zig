const std = @import("std");
const p = @import("zinn").host.progress;
pub fn main(init: std.process.Init) !void {
    const parsed = try p.cli(init);
    var renderer = p.Renderer.init(init, parsed.mode);
    defer renderer.deinit();
    var task = renderer.observer().task("Fixture", 10000);
    errdefer task.fail("fixture failure");
    const wait = parsed.args.len > 1 and std.mem.eql(u8, parsed.args[1], "--wait");
    for (0..10000) |i| {
        task.update(i + 1, &.{.{ .name = "loss", .value = 0.125 }});
        if (wait) try std.Io.sleep(init.io, .fromMilliseconds(10), .awake);
    }
    if (parsed.args.len > 1 and std.mem.eql(u8, parsed.args[1], "--fail")) return error.FixtureFailure;
    task.finish();
    try std.Io.File.stdout().writeStreamingAll(init.io, "{\"fixture\":true}\n");
}
