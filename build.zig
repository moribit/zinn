const std = @import("std");
const ch32 = @import("ch32fun_zig");
pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const core = b.addModule("zinn", .{ .root_source_file = b.path("src/root.zig"), .target = target, .optimize = optimize });
    const tests = b.addTest(.{ .root_module = core });
    b.step("test", "Run core and golden tests").dependOn(&b.addRunArtifact(tests).step);
    {
        const invalid = b.addObject(.{ .name = "invalid_shape", .root_module = b.createModule(.{
            .root_source_file = b.path("tests/invalid_shape.zig"),
            .target = b.graph.host,
            .imports = &.{.{ .name = "zinn", .module = core }},
        }) });
        invalid.expect_errors = .{ .contains = "dense parameter shape mismatch" };
        b.top_level_steps.get("test").?.step.dependOn(&invalid.step);
    }
    {
        const invalid = b.addObject(.{ .name = "invalid_overflow", .root_module = b.createModule(.{
            .root_source_file = b.path("tests/invalid_overflow.zig"),
            .target = b.graph.host,
            .imports = &.{.{ .name = "zinn", .module = core }},
        }) });
        invalid.expect_errors = .{ .contains = "dense accumulator may overflow int32" };
        b.top_level_steps.get("test").?.step.dependOn(&invalid.step);
    }
    {
        const invalid = b.addObject(.{ .name = "invalid_quant", .root_module = b.createModule(.{
            .root_source_file = b.path("tests/invalid_quant.zig"),
            .target = b.graph.host,
            .imports = &.{.{ .name = "zinn", .module = core }},
        }) });
        invalid.expect_errors = .{ .contains = "quantization multiplier must be positive" };
        b.top_level_steps.get("test").?.step.dependOn(&invalid.step);
    }
    {
        const invalid = b.addObject(.{ .name = "invalid_connection", .root_module = b.createModule(.{
            .root_source_file = b.path("tests/invalid_connection.zig"),
            .target = b.graph.host,
            .imports = &.{.{ .name = "zinn", .module = core }},
        }) });
        invalid.expect_errors = .{ .contains = "layer shape mismatch" };
        b.top_level_steps.get("test").?.step.dependOn(&invalid.step);
    }
    {
        const invalid = b.addObject(.{ .name = "invalid_zero", .root_module = b.createModule(.{
            .root_source_file = b.path("tests/invalid_zero.zig"),
            .target = b.graph.host,
            .imports = &.{.{ .name = "zinn", .module = core }},
        }) });
        invalid.expect_errors = .{ .contains = "layer zero point mismatch" };
        b.top_level_steps.get("test").?.step.dependOn(&invalid.step);
    }
    const host = b.addExecutable(.{ .name = "xor", .root_module = b.createModule(.{
        .root_source_file = b.path("examples/xor/host.zig"),
        .target = b.graph.host,
        .optimize = optimize,
        .imports = &.{.{ .name = "zinn", .module = core }},
    }) });
    b.step("xor", "Verify XOR on host").dependOn(&b.addRunArtifact(host).step);
    const bench = b.addExecutable(.{ .name = "xor-benchmark", .root_module = b.createModule(.{
        .root_source_file = b.path("examples/xor/benchmark.zig"),
        .target = b.graph.host,
        .optimize = .fast,
        .imports = &.{.{ .name = "zinn", .module = b.createModule(.{ .root_source_file = b.path("src/root.zig"), .target = b.graph.host, .optimize = .fast }) }},
    }) });
    b.step("benchmark", "Measure host XOR inference (fast)").dependOn(&b.addRunArtifact(bench).step);
    if (b.lazyDependency("ch32fun_zig", .{})) |dep| {
        const fw = ch32.addFirmware(b, dep, .{ .name = "zinn-xor", .root_source_file = b.path("examples/xor/firmware.zig") });
        fw.root_module.strip = false;
        const fw_core = b.createModule(.{ .root_source_file = b.path("src/root.zig"), .target = ch32.ch32Target(b), .optimize = .small });
        fw.root_module.import_table.get("app").?.addImport("zinn", fw_core);
        const size_tool = b.addExecutable(.{ .name = "size", .root_module = b.createModule(.{
            .root_source_file = b.path("tools/size.zig"),
            .target = b.graph.host,
            .optimize = .safe,
        }) });
        const size_run = b.addRunArtifact(size_tool);
        size_run.addFileArg(fw.getEmittedBin());
        b.step("size", "Report ELF memory usage and check budgets").dependOn(&size_run.step);
        const install = b.addInstallArtifact(fw, .{});
        b.step("firmware", "Cross-build CH32V003 XOR ELF").dependOn(&install.step);
    }
}
