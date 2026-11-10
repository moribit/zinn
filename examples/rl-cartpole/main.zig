const std = @import("std");
const app_module = @import("app");
const window = @import("desktop_window");
const m = @import("mimoc_ui");
var app: app_module.App = .{};
var bounded = false;
extern fn rl_window_minimum() void;
fn receive(event: window.Event) void {
    switch (event) {
        .input => |input| app.receive(input),
        .tick => |now| {
            if (!bounded) {
                rl_window_minimum();
                bounded = true;
            }
            app.tick(now);
            app.render();
        },
        .focus_lost => app.display.cancelInput(),
        .resize => {},
    }
    window.present(&app.pixels, .{ .w = app_module.width, .h = app_module.height });
}
pub fn main(init: std.process.Init) !void {
    try app.init();
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    if (args.len == 3 and std.mem.eql(u8, args[1], "--snapshot")) {
        try app.control(23);
        try app.advance(40);
        app.render();
        var file = try std.Io.Dir.cwd().createFile(init.io, args[2], .{});
        defer file.close(init.io);
        try file.writeStreamingAll(init.io, "P4\n640 360\n");
        const surface = try m.surface.Mono1.init(&app.pixels, 640, 360);
        var row: [80]u8 = undefined;
        for (0..360) |y| {
            @memset(&row, 0);
            for (0..640) |x| if (!surface.get(@intCast(x), @intCast(y))) {
                row[x / 8] |= @as(u8, 128) >> @as(u3, @intCast(x % 8));
            };
            try file.writeStreamingAll(init.io, &row);
        }
        return;
    }
    if (args.len != 1) return error.ExpectedNoArgumentsOrSnapshot;
    window.run(&app.pixels, .{ .w = 640, .h = 360 }, 2, "Zinn RL Lab - CartPole", receive);
}
