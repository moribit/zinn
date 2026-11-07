pub const addProject = @import("build_support/project.zig").addProject;
pub const ProjectOptions = @import("build_support/project.zig").Options;
const std = @import("std");
const ch32 = @import("ch32fun_zig");
fn coreModule(b: *std.Build, target: std.Build.ResolvedTarget, optimize: std.lang.Optimize) *std.Build.Module {
    return b.createModule(.{ .root_source_file = b.path("src/root.zig"), .target = target, .optimize = optimize });
}
pub fn build(b: *std.Build) void {
    const target_name = b.option([]const u8, "target", "ch32v003 or a Zig target triple") orelse "native";
    const cpu = b.option([]const u8, "cpu", "Target CPU features");
    const ofmt = b.option([]const u8, "ofmt", "Target object format");
    const dynamic_linker = b.option([]const u8, "dynamic-linker", "Dynamic linker for a host target");
    const target = if (std.mem.eql(u8, target_name, "ch32v003")) ch32.ch32Target(b) else b.resolveTargetQuery(std.Build.parseTargetQuery(.{ .arch_os_abi = target_name, .cpu_features = cpu, .object_format = ofmt, .dynamic_linker = dynamic_linker }) catch @panic("invalid target"));
    const optimize = b.standardOptimizeOption(.{});
    const Project = enum { xor, mnist, csv };
    const selected_project = b.option(Project, "project", "Common workflow project (legacy commands remain available)") orelse .xor;
    const train_alias = b.step("train", "Train the selected project");
    const evaluate_alias = b.step("evaluate", "Evaluate selected project");
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
    const xor_fit_options = b.addOptions();
    xor_fit_options.addOption(bool, "int4", false);
    const xor_fit = b.addExecutable(.{ .name = "zinn-xor-fit", .root_module = b.createModule(.{ .root_source_file = b.path("examples/xor/pipeline.zig"), .target = b.graph.host, .optimize = .safe, .imports = &.{ .{ .name = "zinn", .module = host_core }, .{ .name = "dataset_options", .module = xor_fit_options.createModule() } } }) });
    const training = b.addRunArtifact(xor_fit);
    training.addArg("train");
    const checkpoint = training.addOutputFileArg("xor.zinn");
    const save_checkpoint = b.addInstallFile(checkpoint, "models/xor.zinn");
    if (selected_project == .xor) train_alias.dependOn(&save_checkpoint.step);
    const eval_run = b.addRunArtifact(pipeline);
    eval_run.addArg("eval");
    const model_path = b.option([]const u8, "checkpoint", "Existing XOR .zinn checkpoint (otherwise train automatically)");
    if (model_path) |path| eval_run.addFileArg(b.path(path)) else eval_run.addFileArg(checkpoint);
    b.step("eval", "Evaluate saved float XOR model").dependOn(&eval_run.step);
    if (selected_project == .xor) evaluate_alias.dependOn(&eval_run.step);
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
    const csv_features = b.option(usize, "features", "CSV feature count") orelse 2;
    const csv_classes = b.option(usize, "classes", "CSV class count") orelse 2;
    const csv_hidden = b.option(usize, "hidden", "CSV classifier hidden units") orelse 8;
    const csv_epochs = b.option(usize, "csv-epochs", "CSV training epochs") orelse 2000;
    const csv_header = b.option(bool, "csv-header", "CSV has one header row") orelse false;
    const csv_train_path = b.option([]const u8, "csv-train", "CSV training file") orelse "data/train.csv";
    const csv_test_path = b.option([]const u8, "csv-test", "CSV held-out evaluation file") orelse "data/test.csv";
    const response_tool = b.addExecutable(.{ .name = "uart-response", .root_module = b.createModule(.{ .root_source_file = b.path("tools/uart_response.zig"), .target = b.graph.host, .optimize = .safe, .imports = &.{.{ .name = "protocol", .module = b.createModule(.{ .root_source_file = b.path("src/protocol.zig"), .target = b.graph.host, .optimize = .safe }) }} }) });
    const response_run = b.addRunArtifact(response_tool);
    response_run.addFileArg(.{ .cwd_relative = b.option([]const u8, "expected-json", "Host expected-output JSON for UART capture") orelse "zig-out/inputs/mnist-uart-expected.json" });
    response_run.addFileArg(.{ .cwd_relative = b.option([]const u8, "response-bin", "Captured UART response bytes") orelse "data/response.bin" });
    const response_report = response_run.captureStdOut(.{});
    b.step("check-response", "Verify captured UART frame identity, CRC and all logits").dependOn(&b.addInstallFile(response_report, "reports/uart-response.json").step);
    const csv_options = b.addOptions();
    csv_options.addOption(usize, "features", csv_features);
    csv_options.addOption(usize, "classes", csv_classes);
    csv_options.addOption(usize, "hidden", csv_hidden);
    csv_options.addOption(usize, "epochs", csv_epochs);
    csv_options.addOption(bool, "header", csv_header);
    csv_options.addOption(bool, "int4", weight_format == .int4);
    const csv_tool = b.addExecutable(.{ .name = "zinn-data", .root_module = b.createModule(.{ .root_source_file = b.path("examples/data_classifier/main.zig"), .target = b.graph.host, .optimize = .safe, .imports = &.{ .{ .name = "zinn", .module = coreModule(b, b.graph.host, .safe) }, .{ .name = "csv_options", .module = csv_options.createModule() } } }) });
    const csv_run = b.addRunArtifact(csv_tool);
    csv_run.addFileArg(.{ .cwd_relative = csv_train_path });
    csv_run.addFileArg(.{ .cwd_relative = csv_test_path });
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
    const model_prefix = b.option([]const u8, "run-name", "Unique artifact prefix for validation experiments") orelse b.fmt("mnist-{s}{s}", .{ if (use_fixture) "fixture-" else "", @tagName(architecture) });
    const fixture_tool = b.addExecutable(.{ .name = "mnist-fixture", .root_module = b.createModule(.{ .root_source_file = b.path("tools/mnist_fixture.zig"), .target = b.graph.host, .optimize = .safe }) });
    const fixture_run = b.addRunArtifact(fixture_tool);
    const fixture_dir = fixture_run.addOutputDirectoryArg("mnist-fixture");
    const dataset_options = b.addOptions();
    const hidden = b.option(usize, "mnist-hidden", "MLP hidden width") orelse 16;
    const channels = b.option(usize, "cnn-channels", "CNN output channels") orelse 2;
    const Preprocess = enum { area, nearest };
    const preprocess = b.option(Preprocess, "preprocess", "Input resize algorithm") orelse .area;
    const EvaluationSplit = enum { validation, @"test" };
    const evaluation = b.option(EvaluationSplit, "evaluation-split", "Validation by default; test only for final frozen-model evaluation") orelse .validation;
    const train_limit = b.option(usize, "train-limit", "Training examples before validation split") orelse 60000;
    const validation_count = b.option(usize, "validation-count", "Held-out training examples") orelse 5000;
    const split_seed = b.option(u32, "split-seed", "Fixed validation partition seed, independent of training seed") orelse 24301;
    const decay_every = b.option(usize, "decay-every", "Learning rate schedule period; 0 disables") orelse 10;
    const decay = std.fmt.parseFloat(f32, b.option([]const u8, "decay", "Learning rate decay factor") orelse "0.3") catch @panic("invalid decay");
    const user_epochs = b.option(usize, "mnist-epochs", "Training epochs");
    const batch_size = b.option(usize, "batch-size", "Training minibatch size") orelse 32;
    const learning_rate = b.option([]const u8, "learning-rate", "SGD rate") orelse "0.05";
    const training_seed = b.option(u32, "seed", "Training seed") orelse 42;
    dataset_options.addOption(usize, "hidden", hidden);
    dataset_options.addOption(usize, "channels", channels);
    dataset_options.addOption(bool, "nearest", preprocess == .nearest);
    dataset_options.addOption(bool, "evaluation_test", evaluation == .@"test");
    dataset_options.addOption(usize, "train_limit", train_limit);
    dataset_options.addOption(usize, "validation_count", validation_count);
    dataset_options.addOption(u32, "split_seed", split_seed);
    dataset_options.addOption(usize, "decay_every", decay_every);
    dataset_options.addOption(f32, "decay", decay);
    dataset_options.addOption(bool, "report_json", false);
    dataset_options.addOption(bool, "csv", false);
    dataset_options.addOption(bool, "csv_header", false);
    dataset_options.addOption(bool, "fixture", use_fixture);
    dataset_options.addOption(bool, "cnn", architecture == .cnn);
    dataset_options.addOption(bool, "int4", weight_format == .int4);
    const dataset_config = dataset_options.createModule();
    const pipeline_core = coreModule(b, b.graph.host, .safe);
    const pipeline_model = b.createModule(.{ .root_source_file = b.path("examples/mnist/project_model.zig"), .target = b.graph.host, .optimize = .safe });
    pipeline_model.addImport("zinn", pipeline_core);
    pipeline_model.addImport("dataset_options", dataset_config);
    const mnist_tool = b.addExecutable(.{ .name = "zinn-mnist", .root_module = b.createModule(.{
        .root_source_file = b.path("examples/mnist/pipeline.zig"),
        .target = b.graph.host,
        .optimize = .safe,
        .imports = &.{ .{ .name = "zinn", .module = pipeline_core }, .{ .name = "dataset_options", .module = dataset_config }, .{ .name = "project_model", .module = pipeline_model } },
    }) });
    const data_dir = b.option([]const u8, "data-dir", "Directory containing official MNIST IDX(.gz) files") orelse "data/mnist";
    const names = [_][]const u8{ "train-images-idx3-ubyte.gz", "train-labels-idx1-ubyte.gz", "t10k-images-idx3-ubyte.gz", "t10k-labels-idx1-ubyte.gz" };
    const download = b.addExecutable(.{ .name = "download-mnist", .root_module = b.createModule(.{ .root_source_file = b.path("tools/download_mnist.zig"), .target = b.graph.host, .optimize = .safe }) });
    const download_run = b.addRunArtifact(download);
    download_run.addArg(data_dir);
    download_run.has_side_effects = true;
    b.step("mnist-download", "Explicitly download the four official MNIST gzip files").dependOn(&download_run.step);
    const fit_options = b.addOptions();
    fit_options.addOption(usize, "hidden", hidden);
    fit_options.addOption(usize, "channels", channels);
    fit_options.addOption(bool, "nearest", preprocess == .nearest);
    fit_options.addOption(bool, "evaluation_test", false);
    fit_options.addOption(usize, "train_limit", train_limit);
    fit_options.addOption(usize, "validation_count", validation_count);
    fit_options.addOption(u32, "split_seed", split_seed);
    fit_options.addOption(usize, "decay_every", decay_every);
    fit_options.addOption(f32, "decay", decay);
    fit_options.addOption(bool, "report_json", false);
    fit_options.addOption(bool, "csv", false);
    fit_options.addOption(bool, "csv_header", false);
    fit_options.addOption(bool, "fixture", use_fixture);
    fit_options.addOption(bool, "cnn", architecture == .cnn);
    fit_options.addOption(bool, "int4", false);
    const fit_config = fit_options.createModule();
    const fit_model = b.createModule(.{ .root_source_file = b.path("examples/mnist/project_model.zig"), .target = b.graph.host, .optimize = .safe });
    fit_model.addImport("zinn", pipeline_core);
    fit_model.addImport("dataset_options", fit_config);
    const mnist_fit = b.addExecutable(.{ .name = "zinn-mnist-fit", .root_module = b.createModule(.{ .root_source_file = b.path("examples/mnist/pipeline.zig"), .target = b.graph.host, .optimize = .safe, .imports = &.{ .{ .name = "zinn", .module = pipeline_core }, .{ .name = "dataset_options", .module = fit_config }, .{ .name = "project_model", .module = fit_model } } }) });
    const mnist_training = b.addRunArtifact(mnist_fit);
    mnist_training.addArg("train");
    for (names[0..2]) |name| mnist_training.addFileArg(if (use_fixture) fixture_dir.path(b, name) else .{ .cwd_relative = b.pathJoin(&.{ data_dir, name }) });
    mnist_training.addArgs(&.{ b.fmt("{d}", .{user_epochs orelse 10}), b.fmt("{d}", .{train_limit}), b.fmt("{d}", .{batch_size}), learning_rate, b.fmt("{d}", .{training_seed}) });
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
    const app_checkpoint = b.option([]const u8, "project-checkpoint", "Selected project checkpoint (v1)");
    const input_bin = b.option([]const u8, "input-bin", "Optional raw quantized input bytes for host/UART replay");
    const sample_index = b.option(usize, "sample-index", "Embedded validation/test vector for host replay") orelse 0;
    const sequence = b.option(u16, "sequence", "UART request sequence") orelse 1;
    const RequestMode = enum { infer, info, benchmark };
    const request_mode = b.option(RequestMode, "request", "UART request opcode") orelse .infer;
    const mnist_model_path = b.option([]const u8, "mnist-checkpoint", "Previously saved matching MNIST checkpoint");
    if (mnist_model_path) |path| mnist_export.addFileArg(.{ .cwd_relative = path }) else mnist_export.addFileArg(mnist_checkpoint);
    for (names, 0..) |source_name, i| {
        const name = if (evaluation == .validation and i >= 2) names[i - 2] else source_name;
        mnist_export.addFileArg(if (use_fixture) fixture_dir.path(b, name) else .{ .cwd_relative = b.pathJoin(&.{ data_dir, name }) });
    }
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
    const verify_model = b.createModule(.{ .root_source_file = b.path("examples/mnist/project_model.zig"), .target = b.graph.host, .optimize = .safe });
    verify_model.addImport("zinn", mnist_core);
    verify_model.addImport("dataset_options", dataset_config);
    const mnist_verify = b.addExecutable(.{ .name = "verify-mnist", .root_module = b.createModule(.{ .root_source_file = b.path("examples/mnist/verify.zig"), .target = b.graph.host, .optimize = .safe, .imports = &.{ .{ .name = "trained_model", .module = mnist_model }, .{ .name = "zinn", .module = mnist_core }, .{ .name = "dataset_options", .module = dataset_config }, .{ .name = "project_model", .module = verify_model } } }) });
    const mnist_e2e = b.step("mnist", "Train/evaluate/export and verify generated MNIST integer inference");
    if (mnist_model_path == null) mnist_e2e.dependOn(&save_mnist.step);
    const mnist_verify_run = b.addRunArtifact(mnist_verify);
    if (mnist_model_path) |path| mnist_verify_run.addFileArg(.{ .cwd_relative = path }) else mnist_verify_run.addFileArg(mnist_checkpoint);
    for (names, 0..) |source_name, i| {
        const name = if (evaluation == .validation and i >= 2) names[i - 2] else source_name;
        mnist_verify_run.addFileArg(if (use_fixture) fixture_dir.path(b, name) else .{ .cwd_relative = b.pathJoin(&.{ data_dir, name }) });
    }
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
        const mnist_json = mnist_size.captureStdOut(.{});
        const mnist_size_text = mnist_size.captureStdErr(.{});
        mnist_fw_step.dependOn(&b.addInstallFile(mnist_size_text, b.fmt("reports/{s}-memory.txt", .{mnist_fw.name})).step);
        mnist_fw_step.dependOn(&b.addInstallFile(mnist_json, b.fmt("reports/{s}-memory.json", .{mnist_fw.name})).step);
        const objdump = b.option([]const u8, "objdump", "Optional LLVM objdump for static stack audit") orelse "llvm-objdump";
        const disasm = b.addSystemCommand(&.{ objdump, "-d" });
        disasm.addFileArg(mnist_fw.getEmittedBin());
        const listing = disasm.captureStdOut(.{});
        const stack_tool = b.addExecutable(.{ .name = "stack-report", .root_module = b.createModule(.{ .root_source_file = b.path("tools/stack_report.zig"), .target = b.graph.host, .optimize = .safe, .imports = &.{.{ .name = "stack_audit", .module = b.createModule(.{ .root_source_file = b.path("src/stack_audit.zig"), .target = b.graph.host, .optimize = .safe }) }} }) });
        const stack_run = b.addRunArtifact(stack_tool);
        stack_run.addFileArg(listing);
        stack_run.addArgs(&.{ "runtime.startup._start_c", b.fmt("{d}", .{stack_budget}) });
        const stack_alias = b.step("stack-audit", "Optional static call-chain audit (LLVM objdump required)");
        if (selected_project == .xor) stack_alias.dependOn(&stack_run.step);
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
            const json = run_size.captureStdOut(.{});
            const size_text = run_size.captureStdErr(.{});
            sizes.dependOn(&b.addInstallFile(size_text, b.fmt("reports/{s}-memory.txt", .{spec[1]})).step);
            sizes.dependOn(&b.addInstallFile(json, b.fmt("reports/{s}-memory.json", .{spec[1]})).step);
            if (selected_project == .xor and std.mem.eql(u8, spec[0], "firmware-production")) {
                deploy.dependOn(&install.step);
                deploy.dependOn(&run_size.step);
                const binary = fw.addObjCopy(.{ .format = .binary, .basename = "zinn-trained-production.bin" });
                const bin_install = b.addInstallFile(binary.getOutput(), "firmware/zinn-trained-production.bin");
                deploy.dependOn(&bin_install.step);
            }
        }
        if (selected_project != .xor) {
            const csv = selected_project == .csv;
            const configured_model = b.path(b.option([]const u8, "model", "Custom model module exporting Structure") orelse (if (csv) "examples/data_classifier/project_model.zig" else "examples/mnist/project_model.zig"));
            const project_name = b.option([]const u8, "app-name", "Common workflow artifact name") orelse (if (csv) "classifier" else "mnist-uart");
            if (addProject(b, null, .{
                .name = project_name,
                .model = configured_model,
                .step_prefix = "app-",
                .dataset = if (csv) .{ .csv = .{ .training = .{ .cwd_relative = csv_train_path }, .evaluation = .{ .cwd_relative = csv_test_path }, .header = csv_header } } else .{ .mnist = .{ .directory = if (use_fixture) fixture_dir else .{ .cwd_relative = data_dir }, .fixture = use_fixture } },
                .training = .{ .epochs = if (csv) csv_epochs else user_epochs orelse 20, .batch = batch_size, .rate = std.fmt.parseFloat(f32, learning_rate) catch @panic("invalid learning rate"), .seed = training_seed, .validation_count = if (csv) 0 else validation_count, .split_seed = split_seed, .decay_every = if (csv) 0 else decay_every, .decay = decay, .limit = train_limit },
                .format = if (weight_format == .int4) .int4 else .int8,
                .evaluation = if (evaluation == .@"test") .final_test else .validation,
                .checkpoint = if (app_checkpoint orelse mnist_model_path orelse model_path) |path| .{ .cwd_relative = path } else null,
                .calibration_limit = calibration_limit,
                .evaluation_limit = test_limit,
                .nearest = preprocess == .nearest,
                .builtin_cnn = architecture == .cnn,
                .hidden = if (csv) csv_hidden else hidden,
                .channels = channels,
                .features = csv_features,
                .classes = csv_classes,
                .objdump = objdump,
                .flash_bytes = flash_budget,
                .reserved_flash_bytes = reserved,
                .ram_bytes = ram_budget,
                .stack_bytes = stack_budget,
                .input_bin = if (input_bin) |path| .{ .cwd_relative = path } else null,
                .sample_index = sample_index,
                .sequence = sequence,
                .request = if (request_mode == .benchmark) .benchmark else if (request_mode == .info) .info else .infer,
            })) |project| {
                b.step("simulate-uart", "Host-only framed inference test; no measured MCU values").dependOn(project.simulate);
                stack_alias.dependOn(project.stack_audit);
                train_alias.dependOn(project.train);
                evaluate_alias.dependOn(project.evaluate);
                deploy.dependOn(project.deploy);
                b.step("flash", "Explicit physical flash for selected project").dependOn(project.flash);
                b.step("infer-host", "Infer selected project and emit UART request").dependOn(project.infer_host);
            }
        }
    }
}
