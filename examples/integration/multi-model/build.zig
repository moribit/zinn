const std = @import("std");
const zinn = @import("zinn");
pub fn build(b: *std.Build) void {
    const dep = b.dependency("zinn", .{});
    const trained = zinn.addModel(b, dep, .{
        .name = "sensor",
        .model = b.path("model.zig"),
        .dataset = .{ .csv = .{ .training = b.path("train.csv"), .evaluation = b.path("validation.csv") } },
        .training = .{ .epochs = 2000, .validation_count = 0, .decay_every = 0 },
        .format = .int4,
    });
    const target = b.standardTargetOptions(.{});
    const app = b.addExecutable(.{ .name = "integration", .root_module = b.createModule(.{ .root_source_file = b.path("main.zig"), .target = target, .optimize = .safe }) });
    const infer = zinn.addInferenceModule(b, dep, target, .safe);
    app.root_module.addImport("zinn_infer", infer);
    app.root_module.addImport("sensor_model", trained.createModuleWithCore(b, infer));
    const other = zinn.addModel(b, dep, .{
        .name = "other",
        .model = b.path("other_model.zig"),
        .dataset = .{ .csv = .{ .training = b.path("train.csv"), .evaluation = b.path("validation.csv") } },
        .training = .{ .epochs = 2000, .seed = 7, .validation_count = 0, .decay_every = 0 },
        .format = .int8,
    });
    app.root_module.addImport("other_model", other.createModule(b, target, .safe));
    b.installArtifact(app);
    b.step("run", "Run integer inference in the caller application").dependOn(&b.addRunArtifact(app).step);
}
