const std = @import("std");
pub const Mode = enum { auto, plain, off };
pub fn configure(run: *std.Build.Step.Run, mode: Mode, name: []const u8) void {
    run.setEnvironmentVariable("ZINN_PROGRESS", @tagName(mode));
    if (mode != .auto) run.disable_zig_progress = true;
    run.rename_step_with_output_arg = false;
    run.step.name = name;
}
/// Only the presenter is unconditional; fitting remains a normal cached Run.
pub fn training(b: *std.Build, pkg: *std.Build, fitting: *std.Build.Step.Run, mode: Mode, model: []const u8, public_name: []const u8, checkpoint: []const u8) struct { backend: *std.Build.Step, display: *std.Build.Step } {
    // Programmatic dependency options need not have a CLI representation.
    // Preserve their original cached Build API instead of rejecting the graph.
    for (b.user_input_options.values()) |value| switch (value) {
        .flag, .scalar, .list => {},
        else => {
            const direct = b.step(public_name, "Train/save model (progress in captured log)");
            return .{ .backend = direct, .display = direct };
        },
    };
    const directory = std.Build.LazyPath.cache_root.path(b, b.fmt("zinn-progress/{s}", .{model}));
    fitting.addDirectoryArg2(directory, .{ .prefix = "--progress-journal=", .make_absolute = true });
    const receipt = fitting.addPrefixedOutputFileArg("--progress-receipt=", "training-run.txt");
    const backend_name = b.fmt("_zinn-{s}", .{public_name});
    const backend = b.step(backend_name, "Internal cacheable training artifacts");
    backend.dependOn(&b.addInstallFile(receipt, b.fmt("reports/{s}-training-receipt.txt", .{model})).step);
    const tool = b.addExecutable(.{ .name = b.fmt("{s}-training-display", .{model}), .root_module = b.createModule(.{ .root_source_file = pkg.path("tools/train_watch.zig"), .target = b.graph.host, .optimize = .safe }) });
    const watch = b.addRunArtifact(tool);
    configure(watch, mode, b.fmt("Zinn: training {s}", .{model}));
    watch.disable_zig_progress = true;
    watch.has_side_effects = true;
    watch.addArg(@tagName(mode));
    watch.addDirectoryArg2(directory, .{ .make_absolute = true });
    watch.addDirectoryArg2(.{ .relative = .{ .base = .install_prefix } }, .{ .make_absolute = true });
    watch.addArgs(&.{ model, checkpoint });
    watch.addFileArg(.zig_exe);
    watch.addArgs(&.{ "build", backend_name, "--build-file" });
    watch.addFileArg(b.path("build.zig"));
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
    const display = b.step(public_name, "Train/save model with live progress or cached artifact summary");
    display.dependOn(&watch.step);
    return .{ .backend = backend, .display = display };
}
