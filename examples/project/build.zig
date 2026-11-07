const std = @import("std");
const zinn = @import("zinn");
pub fn build(b: *std.Build) void {
    const dependency = b.dependency("zinn", .{});
    _ = zinn.addProject(b, dependency, .{
        .name = "sensor",
        .model = b.path("model.zig"),
        .dataset = .{ .csv = .{ .training = b.path("train.csv"), .evaluation = b.path("validation.csv") } },
        .training = .{ .epochs = 2000, .validation_count = 0, .decay_every = 0 },
        .format = .int4,
        .target = .ch32v003,
    });
}
