const std = @import("std");
const ch32 = @import("ch32fun_zig");
pub const Format = enum { int8, int4 };
pub const Evaluation = enum { validation, final_test };
pub const Dataset = union(enum) {
    csv: struct { training: std.Build.LazyPath, evaluation: std.Build.LazyPath, header: bool = false },
    mnist: struct { directory: std.Build.LazyPath, fixture: bool = false },
};
pub const Training = struct { epochs: usize = 20, batch: usize = 32, rate: f32 = 0.05, seed: u32 = 42, split_seed: u32 = 24301, validation_count: ?usize = null, decay_every: usize = 10, decay: f32 = 0.3, limit: usize = 60000 };
pub const Options = struct {
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
    target: enum { ch32v003 } = .ch32v003,
    step_prefix: []const u8 = "",
    board_adapter: ?std.Build.LazyPath = null,
    firmware: ?std.Build.LazyPath = null,
    objdump: []const u8 = "llvm-objdump",
    stack_bytes: u32 = 512,
    flash_bytes: u32 = 16384,
    reserved_flash_bytes: u32 = 64,
    ram_bytes: u32 = 2048,
    input_bin: ?std.Build.LazyPath = null,
    sample_index: usize = 0,
    sequence: u16 = 1,
    request: enum { infer, info, benchmark } = .infer,
};
pub const Artifacts = struct { checkpoint: std.Build.LazyPath, source: std.Build.LazyPath, metadata: std.Build.LazyPath, elf: std.Build.LazyPath, bin: std.Build.LazyPath, train: *std.Build.Step, evaluate: *std.Build.Step, deploy: *std.Build.Step, flash: *std.Build.Step, infer_host: *std.Build.Step, stack_audit: *std.Build.Step, simulate: *std.Build.Step };
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
    config.addOption(bool, "evaluation_test", !training and final_test);
    config.addOption(usize, "train_limit", options.training.limit);
    config.addOption(usize, "validation_count", validation_count);
    config.addOption(u32, "split_seed", options.training.split_seed);
    config.addOption(usize, "decay_every", options.training.decay_every);
    config.addOption(f32, "decay", options.training.decay);
    return config.createModule();
}
pub fn addProject(b: *std.Build, dependency: ?*std.Build.Dependency, options: Options) ?Artifacts {
    for (options.name) |c| if (!std.ascii.isAlphanumeric(c) and c != '-' and c != '_') @panic("project name must contain only letters, digits, '-' or '_'");
    const pkg = if (dependency) |d| d.builder else b;
    const hal = pkg.lazyDependency("ch32fun_zig", .{}) orelse return null;
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
    fitting.addArg("train");
    for (train_files) |file| fitting.addFileArg(file);
    fitting.addArgs(&.{ b.fmt("{d}", .{options.training.epochs}), b.fmt("{d}", .{options.training.limit}), b.fmt("{d}", .{options.training.batch}), b.fmt("{d}", .{options.training.rate}), b.fmt("{d}", .{options.training.seed}) });
    const checkpoint = fitting.addOutputFileArg(b.fmt("{s}.zinn", .{options.name}));
    const curve = fitting.captureStdOut(.{});
    const train = b.step(b.fmt("{s}train", .{options.step_prefix}), "Train/save model and validation curve");
    train.dependOn(&b.addInstallFile(checkpoint, b.fmt("training/{s}.zinn", .{options.name})).step);
    train.dependOn(&b.addInstallFile(curve, b.fmt("reports/{s}-training.csv", .{options.name})).step);
    const selected = options.checkpoint orelse checkpoint;
    const exporting = b.addRunArtifact(pipeline);
    exporting.addArg("export");
    exporting.addFileArg(selected);
    for (train_files) |file| exporting.addFileArg(file);
    for (eval_files) |file| exporting.addFileArg(file);
    exporting.addArgs(&.{ b.fmt("{d}", .{options.calibration_limit}), b.fmt("{d}", .{options.evaluation_limit}) });
    const source = exporting.addOutputFileArg(b.fmt("{s}.zig", .{options.name}));
    const metadata = exporting.addOutputFileArg(b.fmt("{s}.json", .{options.name}));
    _ = exporting.captureStdOut(.{});
    const evaluate = b.step(b.fmt("{s}evaluate", .{options.step_prefix}), "Evaluate selected split and emit integer model/metadata");
    evaluate.dependOn(&b.addInstallFile(source, b.fmt("models/{s}-{s}.zig", .{ options.name, @tagName(options.format) })).step);
    evaluate.dependOn(&b.addInstallFile(metadata, b.fmt("reports/{s}-model.json", .{options.name})).step);
    const generated = b.createModule(.{ .root_source_file = source, .target = b.graph.host, .optimize = .safe });
    generated.addImport("zinn", core);
    const verify = b.addExecutable(.{ .name = b.fmt("{s}-verify", .{options.name}), .root_module = b.createModule(.{ .root_source_file = pkg.path("examples/mnist/verify.zig"), .target = b.graph.host, .optimize = .safe, .imports = &.{ .{ .name = "zinn", .module = core }, .{ .name = "dataset_options", .module = opts }, .{ .name = "project_model", .module = projectModel(b, options.model, core, opts) }, .{ .name = "trained_model", .module = generated } } }) });
    const verification = b.addRunArtifact(verify);
    verification.addFileArg(selected);
    for (train_files) |file| verification.addFileArg(file);
    for (eval_files) |file| verification.addFileArg(file);
    verification.addArgs(&.{ b.fmt("{d}", .{options.calibration_limit}), b.fmt("{d}", .{options.evaluation_limit}) });
    evaluate.dependOn(&verification.step);
    const fw = ch32.addFirmware(b, hal, .{ .name = options.name, .root_source_file = options.firmware orelse pkg.path("examples/mnist/uart.zig") });
    fw.root_module.strip = false;
    const fw_core = module(b, pkg, ch32.ch32Target(b), .small);
    const fw_model = b.createModule(.{ .root_source_file = source, .target = ch32.ch32Target(b), .optimize = .small });
    fw_model.addImport("zinn", fw_core);
    const app = fw.root_module.import_table.get("app").?;
    app.addImport("zinn", fw_core);
    app.addImport("trained_model", fw_model);
    const board = b.createModule(.{ .root_source_file = options.board_adapter orelse pkg.path("src/targets/ch32v003_uart.zig"), .target = ch32.ch32Target(b), .optimize = .small });
    board.addImport("ch32fun", app.import_table.get("ch32fun").?);
    app.addImport("board_adapter", board);
    const deploy = b.step(b.fmt("{s}deploy", .{options.step_prefix}), "Emit UART production ELF/bin and validate final capacity; never flashes");
    deploy.dependOn(evaluate);
    deploy.dependOn(&b.addInstallFile(fw.getEmittedBin(), b.fmt("firmware/{s}.elf", .{options.name})).step);
    const binary = fw.addObjCopy(.{ .format = .binary, .basename = b.fmt("{s}.bin", .{options.name}) });
    deploy.dependOn(&b.addInstallFile(binary.getOutput(), b.fmt("firmware/{s}.bin", .{options.name})).step);
    const size_tool = b.addExecutable(.{ .name = b.fmt("{s}-size", .{options.name}), .root_module = b.createModule(.{ .root_source_file = pkg.path("tools/size.zig"), .target = b.graph.host, .optimize = .safe, .imports = &.{.{ .name = "budget", .module = b.createModule(.{ .root_source_file = pkg.path("src/budget.zig"), .target = b.graph.host, .optimize = .safe }) }} }) });
    const size = b.addRunArtifact(size_tool);
    size.addFileArg(fw.getEmittedBin());
    size.addArgs(&.{ b.fmt("{d}", .{options.flash_bytes}), b.fmt("{d}", .{options.ram_bytes}), b.fmt("{d}", .{options.stack_bytes}), b.fmt("{d}", .{options.reserved_flash_bytes}) });
    const size_json = size.captureStdOut(.{});
    const size_text = size.captureStdErr(.{});
    deploy.dependOn(&b.addInstallFile(size_json, b.fmt("reports/{s}-memory.json", .{options.name})).step);
    deploy.dependOn(&b.addInstallFile(size_text, b.fmt("reports/{s}-memory.txt", .{options.name})).step);
    const flash = b.step(b.fmt("{s}flash", .{options.step_prefix}), "Explicitly flash generated binary with chzig/WCH-LinkE");
    const flashing = b.addSystemCommand(&.{ "chzig", "flash", "--no-build", "--bin" });
    flashing.addFileArg(binary.getOutput());
    flashing.step.dependOn(deploy);
    flash.dependOn(&flashing.step);
    const frame_tool = b.addExecutable(.{ .name = b.fmt("{s}-frame", .{options.name}), .root_module = b.createModule(.{ .root_source_file = pkg.path("tools/project_frame.zig"), .target = b.graph.host, .optimize = .safe, .imports = &.{ .{ .name = "zinn", .module = core }, .{ .name = "trained_model", .module = generated } } }) });
    const frame = b.addRunArtifact(frame_tool);
    if (options.input_bin) |input| frame.addFileArg(input) else frame.addArg("-");
    const request = frame.addOutputFileArg("request.bin");
    const expected = frame.addOutputFileArg("expected.json");
    frame.addArgs(&.{ b.fmt("{d}", .{options.sequence}), b.fmt("{d}", .{options.sample_index}), @tagName(options.request) });
    const infer_host = b.step(b.fmt("{s}infer-host", .{options.step_prefix}), "Infer on host and generate reproducible UART request/expected output");
    infer_host.dependOn(&b.addInstallFile(request, b.fmt("inputs/{s}-request.bin", .{options.name})).step);
    infer_host.dependOn(&b.addInstallFile(expected, b.fmt("inputs/{s}-expected.json", .{options.name})).step);
    const simulation_tool = b.addExecutable(.{ .name = b.fmt("{s}-uart-simulation", .{options.name}), .root_module = b.createModule(.{ .root_source_file = pkg.path("tools/uart_simulate.zig"), .target = b.graph.host, .optimize = .safe, .imports = &.{ .{ .name = "zinn", .module = core }, .{ .name = "trained_model", .module = generated } } }) });
    const simulation = b.addRunArtifact(simulation_tool);
    simulation.addFileArg(request);
    const simulated_response = simulation.addOutputFileArg("simulated-response.bin");
    const response_tool = b.addExecutable(.{ .name = b.fmt("{s}-response", .{options.name}), .root_module = b.createModule(.{ .root_source_file = pkg.path("tools/uart_response.zig"), .target = b.graph.host, .optimize = .safe, .imports = &.{.{ .name = "protocol", .module = b.createModule(.{ .root_source_file = pkg.path("src/protocol.zig"), .target = b.graph.host, .optimize = .safe }) }} }) });
    const validate = b.addRunArtifact(response_tool);
    validate.addFileArg(expected);
    validate.addFileArg(simulated_response);
    const simulated_report = validate.captureStdOut(.{});
    const simulate = b.step(b.fmt("{s}simulate-uart", .{options.step_prefix}), "Host-only transport simulation and all-logit comparison (not hardware timing)");
    simulate.dependOn(&b.addInstallFile(simulated_report, b.fmt("reports/{s}-simulated-response.json", .{options.name})).step);
    simulate.dependOn(&b.addInstallFile(simulated_response, b.fmt("reports/{s}-simulated-response.bin", .{options.name})).step);
    const disasm = b.addSystemCommand(&.{ options.objdump, "-d" });
    disasm.addFileArg(fw.getEmittedBin());
    const listing = disasm.captureStdOut(.{});
    const stack_tool = b.addExecutable(.{ .name = b.fmt("{s}-stack", .{options.name}), .root_module = b.createModule(.{ .root_source_file = pkg.path("tools/stack_report.zig"), .target = b.graph.host, .optimize = .safe, .imports = &.{.{ .name = "stack_audit", .module = b.createModule(.{ .root_source_file = pkg.path("src/stack_audit.zig"), .target = b.graph.host, .optimize = .safe }) }} }) });
    const stack_run = b.addRunArtifact(stack_tool);
    stack_run.addFileArg(listing);
    stack_run.addArgs(&.{ "runtime.startup._start_c", b.fmt("{d}", .{options.stack_bytes}) });
    const stack_audit = b.step(b.fmt("{s}stack-audit", .{options.step_prefix}), "Optional normal-path stack estimate using LLVM disassembly");
    stack_audit.dependOn(&stack_run.step);
    return .{ .checkpoint = checkpoint, .source = source, .metadata = metadata, .elf = fw.getEmittedBin(), .bin = binary.getOutput(), .train = train, .evaluate = evaluate, .deploy = deploy, .flash = flash, .infer_host = infer_host, .stack_audit = stack_audit, .simulate = simulate };
}
