const std = @import("std");
pub const Mode = enum { auto, plain, off };
pub const Operation = enum { train, evaluate, e2e, deploy };
pub const Steps = struct { backend: *std.Build.Step, display: *std.Build.Step };
pub fn configure(run: *std.Build.Step.Run, mode: Mode, name: []const u8) void {
    // Keep runtime TERM/CI/environment inheritance: cloning the configuration
    // environment here would freeze terminal capabilities into Build cache.
    run.addArg(run.step.owner.fmt("--progress={s}", .{@tagName(mode)}));
    if (mode != .auto) run.disable_zig_progress = true;
    run.rename_step_with_output_arg = false;
    run.step.name = name;
}
/// Only the presenter is unconditional; fitting remains a normal cached Run.
pub fn training(b: *std.Build, pkg: *std.Build, fitting: *std.Build.Step.Run, mode: Mode, model: []const u8, public_name: []const u8, checkpoint: []const u8) struct { backend: *std.Build.Step, display: *std.Build.Step } {
    const steps = operation(b, pkg, fitting, mode, model, public_name, checkpoint, .train, b.path("build.zig"));
    return .{ .backend = steps.backend, .display = steps.display };
}
pub fn operation(b: *std.Build, pkg: *std.Build, fitting: *std.Build.Step.Run, mode: Mode, model: []const u8, public_name: []const u8, checkpoint: []const u8, kind: Operation, build_file: std.Build.LazyPath) Steps {
    // Programmatic dependency options need not have a CLI representation.
    // Preserve their original cached Build API instead of rejecting the graph.
    for (b.user_input_options.values()) |value| switch (value) {
        .flag, .scalar, .list => {},
        else => {
            const direct = b.step(public_name, "Train/save model (progress in captured log)");
            return .{ .backend = direct, .display = direct };
        },
    };
    const phase = if (kind == .train) "training" else @tagName(kind);
    fitting.disable_zig_progress = true;
    const stderr_log = fitting.captureStdErr(.{});
    const stdout_log = fitting.captureStdOut(.{});
    const directory = std.Build.LazyPath.cache_root.path(b, b.fmt("zinn-progress/{s}-{s}", .{ model, phase }));
    fitting.addDirectoryArg2(directory, .{ .prefix = "--progress-journal=", .make_absolute = true });
    const receipt = fitting.addPrefixedOutputFileArg("--progress-receipt=", "training-run.txt");
    const report = fitting.addPrefixedOutputFileArg("--summary=", "summary.json");
    const backend_name = b.fmt("_zinn-{s}", .{public_name});
    const backend = b.step(backend_name, "Internal cacheable training artifacts");
    backend.dependOn(&b.addInstallFile(receipt, b.fmt("reports/{s}-{s}-receipt.txt", .{ model, phase })).step);
    backend.dependOn(&b.addInstallFile(report, b.fmt("reports/{s}-{s}-summary.json", .{ model, phase })).step);
    if (kind != .train) {
        backend.dependOn(&b.addInstallFile(stderr_log, b.fmt("reports/{s}-{s}-progress.log", .{ model, phase })).step);
        backend.dependOn(&b.addInstallFile(stdout_log, b.fmt("reports/{s}-{s}-output.txt", .{ model, phase })).step);
    }
    const tool = b.addExecutable(.{ .name = b.fmt("{s}-training-display", .{model}), .root_module = b.createModule(.{ .root_source_file = pkg.path("tools/train_watch.zig"), .target = b.graph.host, .optimize = .safe }) });
    tool.root_module.addImport("progress", b.createModule(.{ .root_source_file = pkg.path("src/host/progress.zig"), .target = b.graph.host, .optimize = .safe }));
    const watch = b.addRunArtifact(tool);
    watch.rename_step_with_output_arg = false;
    watch.step.name = b.fmt("Zinn: {s} {s}", .{ phase, model });
    watch.disable_zig_progress = true;
    watch.has_side_effects = true;
    watch.addArg(@tagName(mode));
    watch.addDirectoryArg2(directory, .{ .make_absolute = true });
    watch.addDirectoryArg2(.{ .relative = .{ .base = .install_prefix } }, .{ .make_absolute = true });
    watch.addArgs(&.{ model, checkpoint });
    watch.addArg(@tagName(kind));
    watch.addFileArg(.zig_exe);
    watch.addArgs(&.{ "build", backend_name, "--build-file" });
    watch.addFileArg(build_file);
    watch.addArg("--prefix");
    watch.addDirectoryArg2(.{ .relative = .{ .base = .install_prefix } }, .{ .make_absolute = true });
    watch.addArg("--cache-dir");
    watch.addDirectoryArg2(.cache_root, .{ .make_absolute = true });
    watch.addArgs(&.{ "--color", "off", "--summary", "none" });
    switch (b.graph.release_mode) {
        .off => {},
        .any => watch.addArg("--release"),
        inline else => |tag| watch.addArg("--release=" ++ @tagName(tag)),
    }
    var inputs = b.user_input_options.iterator();
    while (inputs.next()) |entry| switch (entry.value_ptr.*) {
        .flag => watch.addArg(b.fmt("-D{s}", .{entry.key_ptr.*})),
        .scalar => |value| watch.addArg(b.fmt("-D{s}={s}", .{ entry.key_ptr.*, value })),
        .list => |values| for (values.items) |value| watch.addArg(b.fmt("-D{s}={s}", .{ entry.key_ptr.*, value })),
        else => unreachable, // Handled by the compatible direct-build fallback.
    };
    const display = b.step(public_name, b.fmt("{s}: execute cached work and show saved results", .{phase}));
    display.dependOn(&watch.step);
    return .{ .backend = backend, .display = display };
}
