//! Host-only framebuffer/inference costs; excludes compositor and screen refresh.
const std = @import("std");
const a = @import("app");
const model = @import("trained_model");
var app: a.App = .{};
fn now(io: std.Io) i96 {
    return std.Io.Clock.awake.now(io).nanoseconds;
}
pub fn main(init: std.process.Init) !void {
    app.sample();
    var checksum: i64 = 0;
    var times: [5]i96 = undefined;
    inline for (.{ "infer", "trace", "play", "network" }) |kind| {
        for (&times) |*time| {
            var start = now(init.io);
            for (0..6000) |i| {
                if (i == 1000) start = now(init.io);
                if (comptime std.mem.eql(u8, kind, "infer")) {
                    a.Model.infer(&model.inputs[i % 16], &app.logits, &app.workspace);
                } else if (comptime std.mem.eql(u8, kind, "trace")) {
                    a.Model.inferTraced(&model.inputs[i % 16], &app.logits, &app.workspace, &app.trace);
                } else {
                    if (@hasField(a.App, "inspection")) {
                        app.inspection.mode = if (comptime std.mem.eql(u8, kind, "network")) .network else .play;
                        app.inspection.stage = 3;
                    }
                    app.render();
                }
                checksum +%= app.logits[i % 10];
                checksum +%= app.pixels[i % app.pixels.len];
                std.mem.doNotOptimizeAway(&app);
            }
            time.* = @divTrunc(now(init.io) - start, 5000);
        }
        std.mem.sort(i96, &times, {}, std.sort.asc(i96));
        std.debug.print("{s}: median_ns={d} min_ns={d} max_ns={d}\n", .{ kind, times[2], times[0], times[4] });
    }
    std.debug.print("checksum={d}\n", .{checksum});
}
