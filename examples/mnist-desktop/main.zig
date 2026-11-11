const std = @import("std");
const application = @import("app");
const window = @import("desktop_window");
const m = @import("mimoc_ui");
var app: application.App = .{};
fn onEvent(event: window.Event) void {
    switch (event) {
        .input => |input| app.receive(input),
        .focus_lost => {
            app.focusLost();
            app.render();
        },
        .resize => {}, // Fixed logical surface; resizing clips without changing pointer coordinates.
        .tick => |now| if (!app.tick(now)) return, // Redraw only active snapshot animation.
    }
    window.present(&app.pixels, .{ .w = application.width, .h = application.height });
}
pub fn main(init: std.process.Init) !void {
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    app.render();
    if (args.len == 3 and (std.mem.eql(u8, args[1], "--snapshot") or std.mem.eql(u8, args[1], "--snapshot-network") or std.mem.eql(u8, args[1], "--snapshot-step"))) {
        app.sample();
        if (std.mem.eql(u8, args[1], "--snapshot-network")) {
            app.inspection.mode = .network;
            app.inspection.stage = 3;
        }
        if (std.mem.eql(u8, args[1], "--snapshot-step")) {
            app.inspection.mode = .step;
            app.inspection.stage = 1;
        }
        app.render();
        var file = try std.Io.Dir.cwd().createFile(init.io, args[2], .{});
        defer file.close(init.io);
        try file.writeStreamingAll(init.io, "P4\n480 272\n");
        const surface = try m.surface.Mono1.init(&app.pixels, application.width, application.height);
        var row: [application.width / 8]u8 = undefined;
        for (0..application.height) |y| {
            @memset(&row, 0);
            for (0..application.width) |x| if (!surface.get(@intCast(x), @intCast(y))) {
                row[x / 8] |= @as(u8, 128) >> @as(u3, @intCast(x % 8));
            };
            try file.writeStreamingAll(init.io, &row);
        }
        std.debug.print("MNIST snapshot: digit={d} path={s}\n", .{ app.prediction.?, args[2] });
        return;
    }
    if (args.len != 1) return error.ExpectedNoArgumentsOrSnapshotPath;
    window.run(&app.pixels, .{ .w = application.width, .h = application.height }, 2, "Zinn - MNIST / mimoc-ui", onEvent);
}
