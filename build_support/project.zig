const std = @import("std");
const ch32 = @import("ch32fun_zig");
const progress = @import("progress.zig");
const model_build = @import("model.zig");
pub const Format = model_build.Format;
pub const Evaluation = model_build.Evaluation;
pub const Dataset = model_build.Dataset;
pub const Training = model_build.Training;
pub const Options = struct {
    /// Set for nonstandard build script filenames; defaults to build.zig.
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
pub const Artifacts = struct { checkpoint: std.Build.LazyPath, source: std.Build.LazyPath, metadata: std.Build.LazyPath, elf: std.Build.LazyPath, bin: std.Build.LazyPath, train: *std.Build.Step, evaluate: *std.Build.Step, deploy: *std.Build.Step, flash: *std.Build.Step, infer_host: *std.Build.Step, stack_audit: *std.Build.Step, simulate: *std.Build.Step, e2e: ?*std.Build.Step = null };
fn module(b: *std.Build, pkg: *std.Build, target: std.Build.ResolvedTarget, optimize: std.lang.Optimize) *std.Build.Module {
    return b.createModule(.{ .root_source_file = pkg.path("src/root.zig"), .target = target, .optimize = optimize });
}
pub fn addProject(b: *std.Build, dependency: ?*std.Build.Dependency, options: Options) ?Artifacts {
    for (options.name) |c| if (!std.ascii.isAlphanumeric(c) and c != '-' and c != '_') @panic("project name must contain only letters, digits, '-' or '_'");
    const pkg = if (dependency) |d| d.builder else b;
    const hal = pkg.lazyDependency("ch32fun_zig", .{}) orelse return null;
    const trained = model_build.addModel(b, dependency, .{
        .build_file = options.build_file,
        .progress = options.progress,
        .name = options.name,
        .model = options.model,
        .dataset = options.dataset,
        .training = options.training,
        .format = options.format,
        .evaluation = options.evaluation,
        .checkpoint = options.checkpoint,
        .calibration_limit = options.calibration_limit,
        .evaluation_limit = options.evaluation_limit,
        .nearest = options.nearest,
        .builtin_cnn = options.builtin_cnn,
        .hidden = options.hidden,
        .channels = options.channels,
        .features = options.features,
        .classes = options.classes,
        .step_prefix = options.step_prefix,
    });
    const source = trained.source;
    const checkpoint = trained.checkpoint;
    const metadata = trained.metadata;
    const core = trained.host_core;
    const generated = trained.host_generated;
    const build_file = options.build_file orelse b.path("build.zig");
    const fw = ch32.addFirmware(b, hal, .{ .name = options.name, .root_source_file = options.firmware orelse pkg.path("examples/mnist/uart.zig") });
    fw.root_module.strip = false;
    fw.step.name = b.fmt("Zinn: firmware build {s}", .{options.name});
    const fw_core = module(b, pkg, ch32.ch32Target(b), .small);
    const fw_model = b.createModule(.{ .root_source_file = source, .target = ch32.ch32Target(b), .optimize = .small });
    fw_model.addImport("zinn", fw_core);
    const app = fw.root_module.import_table.get("app").?;
    app.addImport("zinn", fw_core);
    app.addImport("trained_model", fw_model);
    const board = b.createModule(.{ .root_source_file = options.board_adapter orelse pkg.path("src/targets/ch32v003_uart.zig"), .target = ch32.ch32Target(b), .optimize = .small });
    board.addImport("ch32fun", app.import_table.get("ch32fun").?);
    app.addImport("board_adapter", board);
    const elf_install = b.addInstallFile(fw.getEmittedBin(), b.fmt("firmware/{s}.elf", .{options.name}));
    const binary = fw.addObjCopy(.{ .format = .binary, .basename = b.fmt("{s}.bin", .{options.name}) });
    const bin_install = b.addInstallFile(binary.getOutput(), b.fmt("firmware/{s}.bin", .{options.name}));
    const memory = @import("memory.zig").addMemoryCheck(b, dependency, .{ .name = options.name, .elf = fw.getEmittedBin(), .flash_bytes = options.flash_bytes, .ram_bytes = options.ram_bytes, .stack_bytes = options.stack_bytes, .reserved_flash_bytes = options.reserved_flash_bytes, .progress = options.progress });
    const size = memory.run;
    const size_json = memory.json;
    const size_text = memory.text;
    const deployment_steps = progress.operation(b, pkg, size, options.progress, options.name, b.fmt("{s}deploy", .{options.step_prefix}), b.fmt("firmware/{s}.elf", .{options.name}), .deploy, build_file);
    const deploy = deployment_steps.backend;
    size.step.dependOn(trained.verification_backend);
    deploy.dependOn(&elf_install.step);
    deploy.dependOn(&bin_install.step);
    deploy.dependOn(&b.addInstallFile(size_json, b.fmt("reports/{s}-memory.json", .{options.name})).step);
    deploy.dependOn(&b.addInstallFile(size_text, b.fmt("reports/{s}-memory.txt", .{options.name})).step);
    const flash = b.step(b.fmt("{s}flash", .{options.step_prefix}), "Explicitly flash generated binary with chzig/WCH-LinkE");
    const flashing = b.addSystemCommand(&.{ "chzig", "flash", "--no-build", "--bin" });
    flashing.addFileArg(binary.getOutput());
    flashing.step.dependOn(deployment_steps.display);
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
    return .{ .checkpoint = checkpoint, .source = source, .metadata = metadata, .elf = fw.getEmittedBin(), .bin = binary.getOutput(), .train = trained.train, .evaluate = trained.evaluate, .deploy = deployment_steps.display, .flash = flash, .infer_host = infer_host, .stack_audit = stack_audit, .simulate = simulate, .e2e = trained.e2e };
}
