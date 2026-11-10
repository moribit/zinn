const std = @import("std");
const progress = @import("progress.zig");
pub const Format = enum { int8, int4 };
pub const Evaluation = enum { validation, final_test };
pub const Dataset = union(enum) {
    csv: struct { training: std.Build.LazyPath, evaluation: std.Build.LazyPath, header: bool = false },
    mnist: struct { directory: std.Build.LazyPath, fixture: bool = false },
};
pub const Training = struct { epochs: usize = 20, batch: usize = 32, rate: f32 = 0.05, seed: u32 = 42, split_seed: u32 = 24301, validation_count: ?usize = null, decay_every: usize = 10, decay: f32 = 0.3, limit: usize = 60000 };
/// Alternative host producer for non-supervised models (for example DQN).
/// The producer owns fitting/calibration/evaluation; Zinn only wires its artifacts.
pub const Generated = struct {
    source: std.Build.LazyPath,
    checkpoint: std.Build.LazyPath,
    metadata: std.Build.LazyPath,
    generate: *std.Build.Step,
    verify: *std.Build.Step,
};
pub const Options = struct {
    generated: ?Generated = null,
    build_file: ?std.Build.LazyPath = null,
    progress: progress.Mode = .auto,
    name: []const u8,
    model: std.Build.LazyPath,
    dataset: Dataset,
    training: Training = .{},
    format: Format = .int8,
    evaluation: Evaluation = .validation,
    checkpoint: ?std.Build.LazyPath = null,
    calibration_limit: usize = 1024,
    evaluation_limit: usize = 10000,
    nearest: bool = false,
    builtin_cnn: bool = false,
    hidden: usize = 16,
    channels: usize = 2,
    features: usize = 2,
    classes: usize = 2,
    step_prefix: ?[]const u8 = null,
};
fn module(b: *std.Build, pkg: *std.Build, target: std.Build.ResolvedTarget, optimize: std.lang.Optimize) *std.Build.Module {
    return b.createModule(.{ .root_source_file = pkg.path("src/root.zig"), .target = target, .optimize = optimize });
}
fn projectModel(b: *std.Build, path: std.Build.LazyPath, core: *std.Build.Module, options: *std.Build.Module) *std.Build.Module {
    const m = b.createModule(.{ .root_source_file = path, .target = b.graph.host, .optimize = .safe });
    m.addImport("zinn", core);
    m.addImport("dataset_options", options);
    return m;
}
fn settings(b: *std.Build, options: Options, validation_count: usize, final_test: bool, training: bool) *std.Build.Module {
    const is_csv = options.dataset == .csv;
    const config = b.addOptions();
    config.addOption(bool, "csv", is_csv);
    config.addOption(bool, "csv_header", if (options.dataset == .csv) options.dataset.csv.header else false);
    config.addOption(bool, "fixture", if (options.dataset == .mnist) options.dataset.mnist.fixture else false);
    config.addOption(bool, "cnn", options.builtin_cnn);
    config.addOption(usize, "hidden", options.hidden);
    config.addOption(usize, "channels", options.channels);
    config.addOption(usize, "features", options.features);
    config.addOption(usize, "classes", options.classes);
    config.addOption(bool, "nearest", options.nearest);
    config.addOption(bool, "int4", !training and options.format == .int4);
    config.addOption(bool, "report_json", true);
    config.addOption([]const u8, "model_name", b.fmt("{s} training", .{options.name}));
    config.addOption(bool, "evaluation_test", !training and final_test);
    config.addOption(usize, "train_limit", options.training.limit);
    config.addOption(usize, "validation_count", validation_count);
    config.addOption(u32, "split_seed", options.training.split_seed);
    config.addOption(usize, "decay_every", options.training.decay_every);
    config.addOption(f32, "decay", options.training.decay);
    return config.createModule();
}
pub const Artifacts = struct {
    source: std.Build.LazyPath,
    checkpoint: std.Build.LazyPath,
    selected_checkpoint: std.Build.LazyPath,
    metadata: std.Build.LazyPath,
    format: Format,
    train: *std.Build.Step,
    evaluate: *std.Build.Step,
    generate: *std.Build.Step,
    e2e: *std.Build.Step,
    // Shared graph nodes used by addProject; consumers normally use the fields above.
    evaluation_backend: *std.Build.Step,
    verification_backend: *std.Build.Step,
    host_core: *std.Build.Module,
    host_generated: *std.Build.Module,
    package: *std.Build,
    pub fn createModule(self: Artifacts, b: *std.Build, target: std.Build.ResolvedTarget, optimize: std.lang.Optimize) *std.Build.Module {
        const core = inferenceModule(b, self.package, target, optimize);
        return self.createModuleWithCore(b, core);
    }
    /// Use when the caller already imports zinn/zinn_infer: one owner per source.
    pub fn createModuleWithCore(self: Artifacts, b: *std.Build, core: *std.Build.Module) *std.Build.Module {
        const generated = b.createModule(.{ .root_source_file = self.source, .target = core.resolved_target, .optimize = core.optimize });
        generated.addImport("zinn", core);
        return generated;
    }
};
pub fn addModel(b: *std.Build, dependency: ?*std.Build.Dependency, options: Options) Artifacts {
    if (options.name.len == 0) @panic("model name must not be empty");
    for (options.name) |c| if (!std.ascii.isAlphanumeric(c) and c != '-' and c != '_') @panic("model name must contain only letters, digits, '-' or '_'");
    const pkg = if (dependency) |d| d.builder else b;
    const prefix = options.step_prefix orelse b.fmt("{s}-", .{options.name});
    if (options.generated) |g| {
        const train = b.step(b.fmt("{s}train", .{prefix}), "Run caller-owned model producer");
        train.dependOn(g.generate);
        const evaluate = b.step(b.fmt("{s}evaluate", .{prefix}), "Read caller-owned model evaluation artifacts");
        evaluate.dependOn(g.generate);
        const generate = b.step(b.fmt("{s}generate", .{prefix}), "Generate caller-owned model source");
        generate.dependOn(g.generate);
        const e2e = b.step(b.fmt("{s}e2e", .{prefix}), "Verify caller-owned integer model");
        e2e.dependOn(g.verify);
        const host = module(b, pkg, b.graph.host, .safe);
        const model = b.createModule(.{ .root_source_file = g.source, .target = b.graph.host, .optimize = .safe });
        model.addImport("zinn", host);
        return .{ .source = g.source, .checkpoint = g.checkpoint, .selected_checkpoint = g.checkpoint, .metadata = g.metadata, .format = options.format, .train = train, .evaluate = evaluate, .generate = generate, .e2e = e2e, .evaluation_backend = g.generate, .verification_backend = g.verify, .host_core = host, .host_generated = model, .package = pkg };
    }

    const is_csv = options.dataset == .csv;
    const validation_count = options.training.validation_count orelse (if (is_csv) @as(usize, 0) else @as(usize, 5000));
    const final_test = options.evaluation == .final_test or (is_csv and validation_count == 0);
    var train_files: [2]std.Build.LazyPath = undefined;
    var eval_files: [2]std.Build.LazyPath = undefined;
    switch (options.dataset) {
        .csv => |csv| {
            train_files = .{ csv.training, csv.training };
            eval_files = .{ csv.evaluation, csv.evaluation };
        },
        .mnist => |mnist| {
            train_files = .{ mnist.directory.path(b, "train-images-idx3-ubyte.gz"), mnist.directory.path(b, "train-labels-idx1-ubyte.gz") };
            eval_files = .{ mnist.directory.path(b, "t10k-images-idx3-ubyte.gz"), mnist.directory.path(b, "t10k-labels-idx1-ubyte.gz") };
        },
    }
    if (!final_test) eval_files = train_files;
    const opts = settings(b, options, validation_count, final_test, false);
    const training_opts = settings(b, options, validation_count, false, true);
    const core = module(b, pkg, b.graph.host, .safe);
    const pipeline = b.addExecutable(.{ .name = b.fmt("{s}-pipeline", .{options.name}), .root_module = b.createModule(.{ .root_source_file = pkg.path("examples/mnist/pipeline.zig"), .target = b.graph.host, .optimize = .safe, .imports = &.{ .{ .name = "zinn", .module = core }, .{ .name = "dataset_options", .module = opts }, .{ .name = "project_model", .module = projectModel(b, options.model, core, opts) } } }) });
    const fit_tool = b.addExecutable(.{ .name = b.fmt("{s}-fit", .{options.name}), .root_module = b.createModule(.{ .root_source_file = pkg.path("examples/mnist/pipeline.zig"), .target = b.graph.host, .optimize = .safe, .imports = &.{ .{ .name = "zinn", .module = core }, .{ .name = "dataset_options", .module = training_opts }, .{ .name = "project_model", .module = projectModel(b, options.model, core, training_opts) } } }) });
    const fitting = b.addRunArtifact(fit_tool);
    progress.configure(fitting, options.progress, b.fmt("Zinn: train {s}", .{options.name}));
    fitting.addArg("train");
    for (train_files) |file| fitting.addFileArg(file);
    fitting.addArgs(&.{ b.fmt("{d}", .{options.training.epochs}), b.fmt("{d}", .{options.training.limit}), b.fmt("{d}", .{options.training.batch}), b.fmt("{d}", .{options.training.rate}), b.fmt("{d}", .{options.training.seed}) });
    const checkpoint = fitting.addOutputFileArg(b.fmt("{s}.zinn", .{options.name}));
    const curve = fitting.captureStdOut(.{});
    const fit_log = fitting.captureStdErr(.{});
    const train_name = b.fmt("{s}train", .{prefix});
    const build_file = options.build_file orelse b.path("build.zig");
    const training_steps = progress.operation(b, pkg, fitting, options.progress, options.name, train_name, b.fmt("training/{s}.zinn", .{options.name}), .train, build_file);
    const train = training_steps.backend;
    train.dependOn(&b.addInstallFile(checkpoint, b.fmt("training/{s}.zinn", .{options.name})).step);
    train.dependOn(&b.addInstallFile(curve, b.fmt("reports/{s}-training.csv", .{options.name})).step);
    train.dependOn(&b.addInstallFile(fit_log, b.fmt("reports/{s}-training-progress.log", .{options.name})).step);
    const selected = options.checkpoint orelse checkpoint;
    const exporting = b.addRunArtifact(pipeline);
    progress.configure(exporting, options.progress, b.fmt("Zinn: evaluate / calibrate / export {s}", .{options.name}));
    exporting.addArg("export");
    exporting.addFileArg(selected);
    for (train_files) |file| exporting.addFileArg(file);
    for (eval_files) |file| exporting.addFileArg(file);
    exporting.addArgs(&.{ b.fmt("{d}", .{options.calibration_limit}), b.fmt("{d}", .{options.evaluation_limit}) });
    const source = exporting.addOutputFileArg(b.fmt("{s}.zig", .{options.name}));
    const metadata = exporting.addOutputFileArg(b.fmt("{s}.json", .{options.name}));
    _ = exporting.captureStdOut(.{});
    const export_log = exporting.captureStdErr(.{});
    const evaluation_steps = progress.operation(b, pkg, exporting, options.progress, options.name, b.fmt("{s}evaluate", .{prefix}), b.fmt("reports/{s}-model.json", .{options.name}), .evaluate, build_file);
    const evaluate = evaluation_steps.backend;
    if (options.checkpoint == null) evaluate.dependOn(training_steps.backend);
    evaluate.dependOn(&b.addInstallFile(source, b.fmt("models/{s}-{s}.zig", .{ options.name, @tagName(options.format) })).step);
    evaluate.dependOn(&b.addInstallFile(metadata, b.fmt("reports/{s}-model.json", .{options.name})).step);
    evaluate.dependOn(&b.addInstallFile(export_log, b.fmt("reports/{s}-export-progress.log", .{options.name})).step);
    const generated = b.createModule(.{ .root_source_file = source, .target = b.graph.host, .optimize = .safe });
    generated.addImport("zinn", core);
    const verify = b.addExecutable(.{ .name = b.fmt("{s}-verify", .{options.name}), .root_module = b.createModule(.{ .root_source_file = pkg.path("examples/mnist/verify.zig"), .target = b.graph.host, .optimize = .safe, .imports = &.{ .{ .name = "zinn", .module = core }, .{ .name = "dataset_options", .module = opts }, .{ .name = "project_model", .module = projectModel(b, options.model, core, opts) }, .{ .name = "trained_model", .module = generated } } }) });
    const verification = b.addRunArtifact(verify);
    progress.configure(verification, options.progress, b.fmt("Zinn: integer reference verification {s}", .{options.name}));
    verification.addFileArg(selected);
    for (train_files) |file| verification.addFileArg(file);
    for (eval_files) |file| verification.addFileArg(file);
    verification.addArgs(&.{ b.fmt("{d}", .{options.calibration_limit}), b.fmt("{d}", .{options.evaluation_limit}) });
    const verification_steps = progress.operation(b, pkg, verification, options.progress, options.name, b.fmt("{s}e2e", .{prefix}), b.fmt("models/{s}-{s}.zig", .{ options.name, @tagName(options.format) }), .e2e, build_file);
    verification_steps.backend.dependOn(evaluate);
    const generate = b.step(b.fmt("{s}generate", .{prefix}), "Evaluate, quantize and export model source (no firmware)");
    generate.dependOn(evaluation_steps.display);
    return .{ .source = source, .checkpoint = checkpoint, .selected_checkpoint = selected, .metadata = metadata, .format = options.format, .train = training_steps.display, .evaluate = evaluation_steps.display, .generate = generate, .e2e = verification_steps.display, .evaluation_backend = evaluate, .verification_backend = verification_steps.backend, .host_core = core, .host_generated = generated, .package = pkg };
}

/// Share one inference source owner across all generated models in a compilation.
pub fn inferenceModule(b: *std.Build, pkg: *std.Build, target: std.Build.ResolvedTarget, optimize: std.lang.Optimize) *std.Build.Module {
    var hash = std.hash.Wyhash.init(0);
    std.hash.autoHash(&hash, target.result.cpu.features);
    hash.update(pkg.root.joinString(b.allocator, "") catch @panic("out of memory"));
    const key = b.fmt("_zinn-infer-{s}-{s}-{x}-{s}", .{ target.result.zigTriple(b.allocator) catch @panic("out of memory"), target.result.cpu.model.name, hash.final(), @tagName(optimize) });
    if (b.modules.get(key)) |existing| return existing;
    return b.addModule(key, .{ .root_source_file = pkg.path("src/infer.zig"), .target = target, .optimize = optimize });
}
