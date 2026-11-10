const std = @import("std");
const zinn = @import("zinn");
pub fn build(b: *std.Build) void {
    const dep = b.dependency("zinn", .{});
    const library_test = b.addTest(.{ .root_module = b.createModule(.{ .root_source_file = b.path("library.zig"), .target = b.graph.host, .optimize = .safe }) });
    library_test.root_module.addImport("zinn_infer", dep.module("zinn_infer"));
    b.step("library-test", "Test the standalone inference-only package entry point").dependOn(&b.addRunArtifact(library_test).step);
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
    const portable = b.step("portability", "Compile integer model objects without a HAL; not board support");
    for ([_]std.Build.ResolvedTarget{
        b.resolveTargetQuery(.{ .cpu_arch = .x86_64, .os_tag = .linux, .abi = .musl }),
        b.resolveTargetQuery(.{ .cpu_arch = .thumb, .os_tag = .freestanding, .abi = .eabi, .cpu_model = .{ .explicit = &std.Target.arm.cpu.cortex_m33 } }),
    }, 0..) |cross, i| {
        const obj = b.addObject(.{ .name = b.fmt("portable-{d}", .{i}), .root_module = b.createModule(.{ .root_source_file = b.path("portable.zig"), .target = cross, .optimize = .small }) });
        obj.root_module.addImport("sensor_model", trained.createModule(b, cross, .small));
        portable.dependOn(&obj.step);
    }
    const full_core = dep.module("zinn");
    const compatibility = b.addExecutable(.{ .name = "full-api-compatibility", .root_module = b.createModule(.{ .root_source_file = b.path("main.zig"), .target = b.graph.host, .optimize = .safe }) });
    compatibility.root_module.addImport("zinn_infer", full_core);
    compatibility.root_module.addImport("sensor_model", trained.createModuleWithCore(b, full_core));
    b.step("compatibility", "Use generated model with the existing full zinn API").dependOn(&b.addRunArtifact(compatibility).step);
    b.installArtifact(app);
    b.step("run", "Run integer inference in the caller application").dependOn(&b.addRunArtifact(app).step);
}
