const std = @import("std");
const zinn = @import("zinn");
pub fn build(b: *std.Build) void {
    const progress = b.option(zinn.ProgressMode, "progress", "Host progress: auto, plain or off") orelse .auto;
    const quiet = b.option(bool, "quiet", "Disable Zinn progress") orelse false;
    const dependency = b.dependency("zinn", .{});
    _ = zinn.addProject(b, dependency, .{
        .name = "sensor",
        .progress = if (quiet) .off else progress,
        .model = b.path("model.zig"),
        .dataset = .{ .csv = .{ .training = b.path("train.csv"), .evaluation = b.path("validation.csv") } },
        .training = .{ .epochs = 2000, .validation_count = 0, .decay_every = 0 },
        .format = .int4,
        .target = .ch32v003,
    });
}
