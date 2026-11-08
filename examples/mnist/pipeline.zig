const std = @import("std");
const z = @import("zinn");
const options = @import("dataset_options");
const S = @import("project_model").Structure;
const T = z.Trainer(S);
const Q = z.export_model.QuantizedFormat(S, if (options.int4) .int4 else .int8);
fn log(init: std.process.Init, comptime fmt: []const u8, args: anytype) !void {
    try std.Io.File.stdout().writeStreamingAll(init.io, try std.fmt.allocPrint(init.arena.allocator(), fmt, args));
}
fn read(init: std.process.Init, path: []const u8) ![]u8 {
    return @import("dataset.zig").read(init, path);
}
fn load(init: std.process.Init, images: []const u8, labels: []const u8, limit: usize) ![]T.Sample {
    return @import("dataset.zig").load(T, init, images, labels, limit);
}
fn number(comptime V: type, bytes: []const u8) !V {
    return std.fmt.parseInt(V, bytes, 10);
}
fn encodeInput(sample: T.Sample, scale: f32) ![S.input_len]i8 {
    var input: [S.input_len]i8 = undefined;
    for (&input, sample.input) |*v, f| v.* = try z.export_model.quantizeInput(f, scale);
    return input;
}
fn class(target: [S.output_len]f32) usize {
    var best: usize = 0;
    for (target, 0..) |v, i| if (v > target[best]) {
        best = i;
    };
    return best;
}
pub fn main(init: std.process.Init) !void {
    const parsed = try z.host.progress.cli(init);
    const args = parsed.args;
    var renderer = z.host.progress.Renderer.init(init, parsed.mode);
    defer renderer.deinit();
    const observer = renderer.observer();
    try run(init, args, observer);
}
fn run(init: std.process.Init, args: []const []const u8, observer: z.host.progress.Observer) !void {
    if (args.len < 2) return error.ExpectedCommand;
    var model = T.init(42);
    if (std.mem.eql(u8, args[1], "train")) {
        if (args.len != 10) return error.ExpectedTrainingArguments;
        const epochs = try number(usize, args[4]);
        const batch = try number(usize, args[6]);
        const rate = try std.fmt.parseFloat(f32, args[7]);
        const seed = try number(u32, args[8]);
        if (epochs == 0 or batch == 0) return error.InvalidTrainingOptions;
        model = T.init(seed);
        var loading = observer.task("Dataset loading", null);
        errdefer loading.fail("dataset load failed");
        const samples = try load(init, args[2], args[3], try number(usize, args[5]));
        loading.finish();
        const partitions = try @import("dataset.zig").partition(T, samples);
        var curve: std.Io.Writer.Allocating = .init(init.arena.allocator());
        const fitted = try z.fit.train(T, &model, partitions.training, partitions.validation, .{ .epochs = epochs, .batch = batch, .rate = rate, .seed = seed, .decay_every = options.decay_every, .decay = options.decay, .observer = observer, .model_name = if (@hasDecl(options, "model_name")) options.model_name else if (options.csv) "CSV training" else if (options.cnn) "MNIST CNN training" else "MNIST MLP training" }, &curve.writer);
        try std.Io.File.stdout().writeStreamingAll(init.io, curve.written());
        try log(init, "# selected_epoch={d} train={d} validation={d} validation_correct={d} validation_ce={d} split_seed={d}\n", .{ fitted.best_epoch, fitted.training_count, fitted.validation_count, fitted.best_validation_correct, fitted.best_validation_loss, options.split_seed });
        // Checkpoint epochs historically counts optimizer steps; preserve that contract.
        const bytes = model.encode();
        try std.Io.Dir.cwd().writeFile(init.io, .{ .sub_path = args[9], .data = &bytes });
    } else if (std.mem.eql(u8, args[1], "export")) {
        if (args.len != 11) return error.ExpectedExportArguments;
        try model.decode(try read(init, args[2]));
        if (options.evaluation_test and (std.mem.eql(u8, args[3], args[5]) or std.mem.eql(u8, args[4], args[6]))) return error.TrainTestPathsMustDiffer;
        var loading = observer.task("Dataset loading", null);
        errdefer loading.fail("dataset load failed");
        const all_train = try load(init, args[3], args[4], options.train_limit);
        const partitions = try @import("dataset.zig").partition(T, all_train);
        const calibration = partitions.training[0..@min(try number(usize, args[7]), partitions.training.len)];
        const testing = if (options.evaluation_test) try load(init, args[5], args[6], try number(usize, args[8])) else partitions.validation[0..@min(try number(usize, args[8]), partitions.validation.len)];
        loading.finish();
        if (testing.len == 0) return error.EmptyValidationSplit;
        const quantized = try Q.calibrateObserved(&model, calibration, observer);
        const evaluation = try model.evaluateObserved(testing, .mse, observer);
        var correct: usize = 0;
        var max_logit_error: f32 = 0;
        var evaluating = observer.task("Quantized evaluation", testing.len);
        errdefer evaluating.fail("evaluation failed");
        for (testing, 0..) |sample, index| {
            const output = quantized.infer(&try encodeInput(sample, quantized.scales[0]));
            correct += @intFromBool(z.argmax(&output).? == class(sample.target));
            const floating = model.predict(&sample.input);
            for (output, floating) |integer, f| max_logit_error = @max(max_logit_error, @abs(@as(f32, @floatFromInt(integer)) * quantized.scales[S.layer_count] - f));
            if (index % 256 == 0 or index + 1 == testing.len) evaluating.update(index + 1, &.{});
        }
        evaluating.finish();
        const report = try std.fmt.allocPrint(init.arena.allocator(), "dataset={s} architecture={s} weights={s} seed={d} optimizer_steps={d} calibration_train_only={d} evaluation_split={s} evaluation_count={d} float_correct={d} float_accuracy={d:.4}% quantized_correct={d} quantized_accuracy={d:.4}% max_logit_error={d:.6}\n", .{ if (options.csv) "CSV" else if (options.fixture) "synthetic-fixture" else "MNIST", if (options.cnn) "cnn" else "mlp", if (options.int4) "int4" else "int8", model.seed, model.epochs, calibration.len, if (options.evaluation_test) "test" else "validation", testing.len, evaluation.correct, 100 * @as(f64, @floatFromInt(evaluation.correct)) / @as(f64, @floatFromInt(testing.len)), correct, 100 * @as(f64, @floatFromInt(correct)) / @as(f64, @floatFromInt(testing.len)), max_logit_error });
        try std.Io.File.stdout().writeStreamingAll(init.io, report);
        if (options.report_json) {
            const parameter_bytes = comptime blk: {
                var n: usize = 0;
                for (S.weight_counts, S.bias_counts) |w, b| n += (if (options.int4) (w + 1) / 2 else w) + 4 * b;
                break :blk n;
            };
            const json = try std.json.Stringify.valueAlloc(init.arena.allocator(), .{
                .schema_version = @as(u32, 1),
                .model_id = quantized.modelId(),
                .schema_tag = S.schema_tag,
                .seed = model.seed,
                .optimizer_steps = model.epochs,
                .preprocessing = if (options.csv) "caller_defined" else if (options.nearest) "nearest28to16_div255" else "area28to16_div255",
                .input_encoding = "signed_i8_twos_complement",
                .layout = if (options.csv) "flat" else "HWC",
                .input_count = S.input_len,
                .output_count = S.output_len,
                .input_scale = quantized.scales[0],
                .input_scale_bits = @as(u32, @bitCast(quantized.scales[0])),
                .zero_point = @as(i8, 0),
                .output_scale = quantized.scales[S.layer_count],
                .weight_format = if (options.int4) "int4" else "int8",
                .parameter_bytes = parameter_bytes,
                .training_count = partitions.training.len,
                .validation_count = partitions.validation.len,
                .calibration_count = calibration.len,
                .evaluation_split = if (options.evaluation_test) "test" else "validation",
                .evaluation_count = testing.len,
                .float_correct = evaluation.correct,
                .quantized_correct = correct,
                .max_logit_error = max_logit_error,
                .hardware_measured = false,
            }, .{});
            try std.Io.Dir.cwd().writeFile(init.io, .{ .sub_path = args[10], .data = json });
        } else try std.Io.Dir.cwd().writeFile(init.io, .{ .sub_path = args[10], .data = report });
        var source: std.Io.Writer.Allocating = .init(init.arena.allocator());
        var exporting = observer.task("Source export", null);
        errdefer exporting.fail("source export failed");
        try quantized.writeSource(&source.writer);
        const count = @min(16, testing.len);
        try quantized.writeVerification(&source.writer, testing[0..count]);
        try std.Io.Dir.cwd().writeFile(init.io, .{ .sub_path = args[9], .data = source.written() });
        exporting.finish();
    } else return error.UnknownCommand;
}
