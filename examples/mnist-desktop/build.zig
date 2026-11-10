const std = @import("std");
const zinn = @import("zinn");
pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const dep = b.dependency("zinn", .{});
    const ui_dep = b.dependency("mimoc_ui", .{ .target = target, .optimize = optimize });
    const ui = ui_dep.module("mimoc_ui");
    const core = zinn.addInferenceModule(b, dep, target, optimize);
    var source = b.path("assets/mnist-mlp32-int8.zig");
    if (b.option(bool, "generate-model", "Train/export with real MNIST instead of bundled model") orelse false) {
        const data = b.option([]const u8, "data-dir", "Directory with four MNIST gzip files") orelse @panic("generate-model requires -Ddata-dir=/path/to/mnist");
        const checkpoint = b.option([]const u8, "checkpoint", "Optional MLP32 checkpoint; otherwise train");
        const trained = zinn.addModel(b, dep, .{
            .name = "desktop-mnist",
            .model = b.path("model.zig"),
            .dataset = .{ .mnist = .{ .directory = .{ .cwd_relative = data } } },
            .checkpoint = if (checkpoint) |path| .{ .cwd_relative = path } else null,
            .training = .{ .epochs = 20, .rate = 0.1, .seed = 42 },
            .format = .int8,
        });
        source = trained.source;
        const generate = b.step("generate", "Evaluate/calibrate/export real MNIST; no firmware");
        generate.dependOn(trained.generate);
        generate.dependOn(&b.addInstallFile(source, "models/mnist-mlp32-int8.zig").step);
        const refresh = b.addUpdateSourceFiles();
        refresh.addCopyFileToSource(source, "assets/mnist-mlp32-int8.zig");
        refresh.addCopyFileToSource(trained.metadata, "assets/model.json");
        // Stage even an already-bundled checkpoint before refreshing source assets.
        const staged = b.addWriteFiles().addCopyFile(trained.selected_checkpoint, "model.zinn");
        refresh.addCopyFileToSource(staged, "assets/model.zinn");
        b.step("refresh-bundle", "Explicitly update committed model assets from generated artifacts").dependOn(&refresh.step);
        b.step("train", "Train MLP32 with the shared Pure Zig pipeline").dependOn(trained.train);
    }
    const model = b.createModule(.{ .root_source_file = source, .target = target, .optimize = optimize });
    model.addImport("zinn", core);
    const controller = b.createModule(.{ .root_source_file = b.path("app.zig"), .target = target, .optimize = optimize });
    controller.addImport("mimoc_ui", ui);
    controller.addImport("trained_model", model);
    controller.addImport("zinn_data", b.createModule(.{ .root_source_file = dep.path("src/data.zig"), .target = target, .optimize = optimize }));
    const tests = b.addTest(.{ .root_module = controller });
    b.step("check", "Compile headless app/tests for the selected target").dependOn(&tests.step);
    b.step("test", "Headless canvas, preprocessing, input and integer inference tests").dependOn(&b.addRunArtifact(tests).step);
    if (target.result.os.tag == .macos) {
        const app = b.addExecutable(.{ .name = "zinn-mnist-desktop", .root_module = b.createModule(.{ .root_source_file = b.path("main.zig"), .target = target, .optimize = optimize }) });
        app.root_module.addImport("app", controller);
        app.root_module.addImport("mimoc_ui", ui);
        const window = b.createModule(.{ .root_source_file = ui_dep.path("src/platform/macos/window.zig"), .target = target, .optimize = optimize });
        window.addImport("mimoc_ui", ui);
        app.root_module.addImport("desktop_window", window);
        app.root_module.addCSourceFile(.{ .file = ui_dep.path("src/platform/macos/window.m"), .flags = &.{"-fobjc-arc"} });
        app.root_module.linkFramework("AppKit", .{});
        app.root_module.linkFramework("Foundation", .{});
        app.root_module.link_libc = true;
        b.installArtifact(app);
        b.getInstallStep().dependOn(&b.addInstallFile(app.getEmittedBin(), "Zinn MNIST.app/Contents/MacOS/zinn-mnist-desktop").step);
        b.getInstallStep().dependOn(&b.addInstallFile(b.path("Info.plist"), "Zinn MNIST.app/Contents/Info.plist").step);
        const run = b.addRunArtifact(app);
        run.addPassthruArgs();
        b.step("run", "Draw digits in the mimoc-ui macOS window").dependOn(&run.step);
    }
}
