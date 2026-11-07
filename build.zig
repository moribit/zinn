const std = @import("std");
const ch32 = @import("ch32fun_zig");
fn coreModule(b: *std.Build, target: std.Build.ResolvedTarget, optimize: std.lang.Optimize) *std.Build.Module {
    return b.createModule(.{ .root_source_file = b.path("src/root.zig"), .target = target, .optimize = optimize });
}
pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const core = b.addModule("zinn", .{ .root_source_file = b.path("src/root.zig"), .target = target, .optimize = optimize });
    const host_core = coreModule(b, b.graph.host, optimize);
    const test_step = b.step("test", "Run unit/golden and compile-fail tests");
    const tests = b.addTest(.{ .root_module = host_core });
    test_step.dependOn(&b.addRunArtifact(tests).step);
    const invalid_cases = .{
        .{ "int4_padding", "unused int4 high nibble must be zero" },
        .{ "int4_shape", "packed int4 weight shape mismatch" },
        .{ "conv_overflow", "convolution accumulator may overflow int32" },
        .{ "conv_shape", "kernel exceeds padded input shape" },
        .{ "spatial_connection", "layer spatial shape mismatch" },
        .{ "model_budget", "model parameters exceed target Flash budget (runtime not yet included)" },
        .{ "shape", "dense parameter shape mismatch" },
        .{ "overflow", "dense accumulator may overflow int32" },
        .{ "quant", "quantization multiplier must be positive" },
        .{ "connection", "layer shape mismatch" },
        .{ "zero", "layer zero point mismatch" },
        .{ "scale", "layer scale mismatch (including missing metadata)" },
        .{ "coefficient", "requantization coefficient disagrees with scales" },
        .{ "tensor_zero", "tensor dimension must be positive" },
        .{ "tensor_empty", "tensor requires dimensions" },
        .{ "tensor_overflow", "tensor size overflow" },
        .{ "missing_scale", "quantization scales must be specified together" },
        .{ "nonfinite_scale", "quantization scale must be finite and positive" },
    };
    inline for (invalid_cases) |case| {
        const invalid = b.addObject(.{ .name = b.fmt("invalid_{s}", .{case[0]}), .root_module = b.createModule(.{
            .root_source_file = b.path(b.fmt("tests/invalid_{s}.zig", .{case[0]})),
            .target = b.graph.host,
            .imports = &.{.{ .name = "zinn", .module = host_core }},
        }) });
        invalid.expect_errors = .{ .contains = case[1] };
        test_step.dependOn(&invalid.step);
    }
    const host = b.addExecutable(.{ .name = "xor", .root_module = b.createModule(.{
        .root_source_file = b.path("examples/xor/host.zig"),
        .target = b.graph.host,
        .optimize = optimize,
        .imports = &.{.{ .name = "zinn", .module = host_core }},
    }) });
    b.step("xor", "Verify original hand-authored XOR golden vectors").dependOn(&b.addRunArtifact(host).step);
    const bench = b.addExecutable(.{ .name = "xor-benchmark", .root_module = b.createModule(.{
        .root_source_file = b.path("examples/xor/benchmark.zig"),
        .target = b.graph.host,
        .optimize = .fast,
        .imports = &.{.{ .name = "zinn", .module = coreModule(b, b.graph.host, .fast) }},
    }) });
    b.step("benchmark", "Measure host XOR inference (fast)").dependOn(&b.addRunArtifact(bench).step);

    const WeightFormat = enum { int8, int4 };
    const weight_format = b.option(WeightFormat, "weight-format", "Exported weight representation") orelse .int8;
    const xor_options = b.addOptions();
    xor_options.addOption(bool, "int4", weight_format == .int4);
    const pipeline = b.addExecutable(.{ .name = "zinn-xor-pipeline", .root_module = b.createModule(.{
        .root_source_file = b.path("examples/xor/pipeline.zig"),
        .target = b.graph.host,
        .optimize = .safe,
        .imports = &.{.{ .name = "zinn", .module = host_core }},
    }) });
    pipeline.root_module.addImport("dataset_options", xor_options.createModule());
    const training = b.addRunArtifact(pipeline);
    training.addArg("train");
    const checkpoint = training.addOutputFileArg("xor.zinn");
    const save_checkpoint = b.addInstallFile(checkpoint, "models/xor.zinn");
    b.step("train", "Train XOR and save zig-out/models/xor.zinn").dependOn(&save_checkpoint.step);
    const eval_run = b.addRunArtifact(pipeline);
    eval_run.addArg("eval");
    const model_path = b.option([]const u8, "checkpoint", "Existing XOR .zinn checkpoint (otherwise train automatically)");
    if (model_path) |path| eval_run.addFileArg(b.path(path)) else eval_run.addFileArg(checkpoint);
    b.step("eval", "Evaluate saved float XOR model").dependOn(&eval_run.step);
    const quantize = b.addRunArtifact(pipeline);
    quantize.addArg("quantize");
    if (model_path) |path| quantize.addFileArg(b.path(path)) else quantize.addFileArg(checkpoint);
    const source = quantize.addOutputFileArg("xor.zig");
    const save_source = b.addInstallFile(source, "models/xor.zig");
    b.step("quantize", "Calibrate and emit zig-out/models/xor.zig").dependOn(&save_source.step);
    const generated = b.createModule(.{ .root_source_file = source, .target = b.graph.host, .optimize = optimize });
    generated.addImport("zinn", host_core);
    const verify = b.addExecutable(.{ .name = "verify-trained-xor", .root_module = b.createModule(.{
        .root_source_file = b.path("examples/xor/verify_trained.zig"),
        .target = b.graph.host,
        .optimize = optimize,
        .imports = &.{ .{ .name = "zinn", .module = host_core }, .{ .name = "trained_model", .module = generated } },
    }) });
    const e2e = b.step("e2e", "Train/save/load/quantize/compile/verify integer XOR");
    e2e.dependOn(&b.addRunArtifact(verify).step);
    e2e.dependOn(&eval_run.step);
    e2e.dependOn(&save_checkpoint.step);
    e2e.dependOn(&save_source.step);
    const csv_options = b.addOptions();
    csv_options.addOption(usize, "features", b.option(usize, "features", "CSV feature count") orelse 2);
    csv_options.addOption(usize, "classes", b.option(usize, "classes", "CSV class count") orelse 2);
    csv_options.addOption(usize, "hidden", b.option(usize, "hidden", "CSV classifier hidden units") orelse 8);
    csv_options.addOption(usize, "epochs", b.option(usize, "csv-epochs", "CSV training epochs") orelse 2000);
    csv_options.addOption(bool, "header", b.option(bool, "csv-header", "CSV has one header row") orelse false);
    csv_options.addOption(bool, "int4", weight_format == .int4);
    const csv_tool = b.addExecutable(.{ .name = "zinn-data", .root_module = b.createModule(.{ .root_source_file = b.path("examples/data_classifier/main.zig"), .target = b.graph.host, .optimize = .safe, .imports = &.{ .{ .name = "zinn", .module = coreModule(b, b.graph.host, .safe) }, .{ .name = "csv_options", .module = csv_options.createModule() } } }) });
    const csv_run = b.addRunArtifact(csv_tool);
    csv_run.addFileArg(.{ .cwd_relative = b.option([]const u8, "csv-train", "CSV training file") orelse "data/train.csv" });
    csv_run.addFileArg(.{ .cwd_relative = b.option([]const u8, "csv-test", "CSV held-out evaluation file") orelse "data/test.csv" });
    const csv_checkpoint = csv_run.addOutputFileArg("classifier.zinn");
    const csv_source = csv_run.addOutputFileArg("classifier.zig");
    const csv_step = b.step("data-train", "Train/evaluate/export CSV classifier using -Dcsv-train and -Dcsv-test");
    csv_step.dependOn(&b.addInstallFile(csv_checkpoint, "models/classifier.zinn").step);
    csv_step.dependOn(&b.addInstallFile(csv_source, "models/classifier.zig").step);
    const csv_core = coreModule(b, b.graph.host, .safe);
    const csv_model = b.createModule(.{ .root_source_file = csv_source, .target = b.graph.host, .optimize = .safe });
    csv_model.addImport("zinn", csv_core);
    const csv_verify = b.addExecutable(.{ .name = "verify-csv", .root_module = b.createModule(.{ .root_source_file = b.path("examples/data_classifier/verify.zig"), .target = b.graph.host, .optimize = .safe, .imports = &.{.{ .name = "trained_model", .module = csv_model }} }) });
    csv_step.dependOn(&b.addRunArtifact(csv_verify).step);
    const Arch = enum { mlp, cnn };
    const architecture = b.option(Arch, "mnist-model", "MNIST architecture") orelse .mlp;
    const use_fixture = b.option(bool, "mnist-fixture", "Use synthetic offline test fixtures, not MNIST data") orelse false;
    const model_prefix = b.fmt("mnist-{s}{s}", .{ if (use_fixture) "fixture-" else "", @tagName(architecture) });
    const fixture_tool = b.addExecutable(.{ .name = "mnist-fixture", .root_module = b.createModule(.{ .root_source_file = b.path("tools/mnist_fixture.zig"), .target = b.graph.host, .optimize = .safe }) });
    const fixture_run = b.addRunArtifact(fixture_tool);
    const fixture_dir = fixture_run.addOutputDirectoryArg("mnist-fixture");
    const dataset_options = b.addOptions();
    dataset_options.addOption(bool, "fixture", use_fixture);
    dataset_options.addOption(bool, "cnn", architecture == .cnn);
    dataset_options.addOption(bool, "int4", weight_format == .int4);
    const mnist_tool = b.addExecutable(.{ .name = "zinn-mnist", .root_module = b.createModule(.{
        .root_source_file = b.path("examples/mnist/pipeline.zig"),
        .target = b.graph.host,
        .optimize = .safe,
        .imports = &.{ .{ .name = "zinn", .module = coreModule(b, b.graph.host, .safe) }, .{ .name = "dataset_options", .module = dataset_options.createModule() } },
    }) });
    const data_dir = b.option([]const u8, "data-dir", "Directory containing official MNIST IDX(.gz) files") orelse "data/mnist";
    const names = [_][]const u8{ "train-images-idx3-ubyte.gz", "train-labels-idx1-ubyte.gz", "t10k-images-idx3-ubyte.gz", "t10k-labels-idx1-ubyte.gz" };
    const download = b.addExecutable(.{ .name = "download-mnist", .root_module = b.createModule(.{ .root_source_file = b.path("tools/download_mnist.zig"), .target = b.graph.host, .optimize = .safe }) });
    const download_run = b.addRunArtifact(download);
    download_run.addArg(data_dir);
    download_run.has_side_effects = true;
    b.step("mnist-download", "Explicitly download the four official MNIST gzip files").dependOn(&download_run.step);
    const mnist_training = b.addRunArtifact(mnist_tool);
    mnist_training.addArg("train");
    for (names[0..2]) |name| mnist_training.addFileArg(if (use_fixture) fixture_dir.path(b, name) else .{ .cwd_relative = b.pathJoin(&.{ data_dir, name }) });
    mnist_training.addArgs(&.{ b.fmt("{d}", .{b.option(usize, "mnist-epochs", "Training epochs") orelse 10}), b.fmt("{d}", .{b.option(usize, "train-limit", "Training examples (default full split)") orelse 60000}), b.fmt("{d}", .{b.option(usize, "batch-size", "Training minibatch size") orelse 32}), b.option([]const u8, "learning-rate", "SGD rate") orelse "0.05", b.fmt("{d}", .{b.option(u32, "seed", "Training seed") orelse 42}) });
    const mnist_checkpoint = mnist_training.addOutputFileArg("mnist.zinn");
    const mnist_training_log = mnist_training.captureStdOut(.{});
    const save_training_log = b.addInstallFile(mnist_training_log, b.fmt("models/{s}-training.txt", .{model_prefix}));
    const save_mnist = b.addInstallFile(mnist_checkpoint, b.fmt("models/{s}.zinn", .{model_prefix}));
    const mnist_train_step = b.step("mnist-train", "Train MNIST on training split only");
    mnist_train_step.dependOn(&save_mnist.step);
    mnist_train_step.dependOn(&save_training_log.step);
    const calibration_limit = b.option(usize, "calibration-limit", "Train-only calibration samples") orelse 1024;
    const test_limit = b.option(usize, "test-limit", "Held-out test samples") orelse 10000;
    const mnist_export = b.addRunArtifact(mnist_tool);
    mnist_export.addArg("export");
    const mnist_model_path = b.option([]const u8, "mnist-checkpoint", "Previously saved matching MNIST checkpoint");
    if (mnist_model_path) |path| mnist_export.addFileArg(.{ .cwd_relative = path }) else mnist_export.addFileArg(mnist_checkpoint);
    for (names) |name| mnist_export.addFileArg(if (use_fixture) fixture_dir.path(b, name) else .{ .cwd_relative = b.pathJoin(&.{ data_dir, name }) });
    mnist_export.addArgs(&.{ b.fmt("{d}", .{calibration_limit}), b.fmt("{d}", .{test_limit}) });
    const mnist_source = mnist_export.addOutputFileArg("mnist.zig");
    const mnist_report = mnist_export.addOutputFileArg("mnist-report.txt");
    const save_mnist_source = b.addInstallFile(mnist_source, b.fmt("models/{s}-{s}.zig", .{ model_prefix, @tagName(weight_format) }));
    const save_mnist_report = b.addInstallFile(mnist_report, b.fmt("models/{s}-{s}-report.txt", .{ model_prefix, @tagName(weight_format) }));
    const mnist_eval = b.step("mnist-eval", "Evaluate held-out split and export calibrated model");
    mnist_eval.dependOn(&save_mnist_source.step);
    mnist_eval.dependOn(&save_mnist_report.step);
    const mnist_model = b.createModule(.{ .root_source_file = mnist_source, .target = b.graph.host, .optimize = .safe });
    const mnist_core = coreModule(b, b.graph.host, .safe);
    mnist_model.addImport("zinn", mnist_core);
    const mnist_verify = b.addExecutable(.{ .name = "verify-mnist", .root_module = b.createModule(.{ .root_source_file = b.path("examples/mnist/verify.zig"), .target = b.graph.host, .optimize = .safe, .imports = &.{ .{ .name = "trained_model", .module = mnist_model }, .{ .name = "zinn", .module = mnist_core }, .{ .name = "dataset_options", .module = dataset_options.createModule() } } }) });
    const mnist_e2e = b.step("mnist", "Train/evaluate/export and verify generated MNIST integer inference");
    if (mnist_model_path == null) mnist_e2e.dependOn(&save_mnist.step);
    const mnist_verify_run = b.addRunArtifact(mnist_verify);
    if (mnist_model_path) |path| mnist_verify_run.addFileArg(.{ .cwd_relative = path }) else mnist_verify_run.addFileArg(mnist_checkpoint);
    for (names) |name| mnist_verify_run.addFileArg(if (use_fixture) fixture_dir.path(b, name) else .{ .cwd_relative = b.pathJoin(&.{ data_dir, name }) });
    mnist_verify_run.addArgs(&.{ b.fmt("{d}", .{calibration_limit}), b.fmt("{d}", .{test_limit}) });
    mnist_e2e.dependOn(&mnist_verify_run.step);
    mnist_e2e.dependOn(&save_mnist_source.step);
    mnist_e2e.dependOn(&save_mnist_report.step);
    _ = core;
    if (b.lazyDependency("ch32fun_zig", .{})) |dep| {
        const size_tool = b.addExecutable(.{ .name = "size", .root_module = b.createModule(.{ .root_source_file = b.path("tools/size.zig"), .target = b.graph.host, .optimize = .safe }) });
        size_tool.root_module.addImport("budget", b.createModule(.{ .root_source_file = b.path("src/budget.zig"), .target = b.graph.host, .optimize = .safe }));
        const flash_budget = b.option(u32, "flash-bytes", "Physical Flash budget") orelse 16384;
        const ram_budget = b.option(u32, "ram-bytes", "Physical SRAM budget") orelse 2048;
        const stack_budget = b.option(u32, "stack-bytes", "Stack allowance (not a measurement)") orelse 512;
        const reserved = b.option(u32, "reserved-flash-bytes", "Reserved Flash outside loadable image") orelse 64;
        const mnist_fw = ch32.addFirmware(b, dep, .{ .name = b.fmt("zinn-{s}-{s}", .{ model_prefix, @tagName(weight_format) }), .root_source_file = b.path("examples/mnist/firmware.zig") });
        mnist_fw.root_module.strip = false;
        const mnist_fw_core = coreModule(b, ch32.ch32Target(b), .small);
        const mnist_fw_model = b.createModule(.{ .root_source_file = mnist_source, .target = ch32.ch32Target(b), .optimize = .small });
        mnist_fw_model.addImport("zinn", mnist_fw_core);
        const mnist_app = mnist_fw.root_module.import_table.get("app").?;
        mnist_app.addImport("zinn", mnist_fw_core);
        mnist_app.addImport("trained_model", mnist_fw_model);
        const mnist_fw_step = b.step("mnist-firmware", "Cross-build generated MNIST for CH32V003 and check final capacity");
        mnist_fw_step.dependOn(&b.addInstallArtifact(mnist_fw, .{}).step);
        const mnist_size = b.addRunArtifact(size_tool);
        mnist_size.addFileArg(mnist_fw.getEmittedBin());
        mnist_size.addArgs(&.{ b.fmt("{d}", .{flash_budget}), b.fmt("{d}", .{ram_budget}), b.fmt("{d}", .{stack_budget}), b.fmt("{d}", .{reserved}) });
        mnist_fw_step.dependOn(&mnist_size.step);
        const fw_specs = .{
            .{ "firmware", "zinn-xor", "examples/xor/firmware.zig", false },
            .{ "firmware-trained", "zinn-trained-diagnostic", "examples/xor/firmware_trained.zig", true },
            .{ "firmware-production", "zinn-trained-production", "examples/xor/production.zig", true },
        };
        const sizes = b.step("size", "Report and check all firmware memory budgets");
        const deploy = b.step("deploy", "Generate production ELF and flashable binary (does not flash hardware)");
        inline for (fw_specs) |spec| {
            const fw = ch32.addFirmware(b, dep, .{ .name = spec[1], .root_source_file = b.path(spec[2]) });
            fw.root_module.strip = false;
            const app = fw.root_module.import_table.get("app").?;
            const fw_core = coreModule(b, ch32.ch32Target(b), .small);
            app.addImport("zinn", fw_core);
            if (spec[3]) {
                const firmware_model = b.createModule(.{ .root_source_file = source, .target = ch32.ch32Target(b), .optimize = .small });
                firmware_model.addImport("zinn", fw_core);
                app.addImport("trained_model", firmware_model);
            }
            const install = b.addInstallArtifact(fw, .{});
            b.step(spec[0], "Cross-build CH32V003 firmware").dependOn(&install.step);
            const run_size = b.addRunArtifact(size_tool);
            run_size.addFileArg(fw.getEmittedBin());
            run_size.addArgs(&.{ b.fmt("{d}", .{flash_budget}), b.fmt("{d}", .{ram_budget}), b.fmt("{d}", .{stack_budget}), b.fmt("{d}", .{reserved}) });
            sizes.dependOn(&run_size.step);
            if (std.mem.eql(u8, spec[0], "firmware-production")) {
                deploy.dependOn(&install.step);
                deploy.dependOn(&run_size.step);
                const binary = fw.addObjCopy(.{ .format = .binary, .basename = "zinn-trained-production.bin" });
                const bin_install = b.addInstallFile(binary.getOutput(), "firmware/zinn-trained-production.bin");
                deploy.dependOn(&bin_install.step);
            }
        }
    }
}
