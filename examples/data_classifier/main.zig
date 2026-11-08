const std = @import("std");
const z = @import("zinn");
const options = @import("csv_options");
const S = z.Definition(options.features, &.{ .{ .units = options.hidden, .activation = .relu }, .{ .units = options.classes } });
const T = z.Trainer(S);
pub fn main(init: std.process.Init) !void {
    const parsed = try z.host.progress.cli(init);
    const args = parsed.args;
    var renderer = z.host.progress.Renderer.init(init, parsed.mode);
    defer renderer.deinit();
    const observer = renderer.observer();
    if (args.len != 5) return error.ExpectedTrainCsvTestCsvCheckpointSource;
    if (std.mem.eql(u8, args[1], args[2])) return error.TrainTestPathsMustDiffer;
    const a = init.arena.allocator();
    var loading = observer.task("CSV dataset loading", null);
    errdefer loading.fail("CSV dataset failed");
    const train_text = try std.Io.Dir.cwd().readFileAlloc(init.io, args[1], a, .limited(64 * 1024 * 1024));
    const test_text = try std.Io.Dir.cwd().readFileAlloc(init.io, args[2], a, .limited(64 * 1024 * 1024));
    const training = try z.data.csv(T, a, train_text, options.header);
    const testing = try z.data.csv(T, a, test_text, options.header);
    loading.finish();
    var model = T.init(42);
    var fitting = observer.task("CSV training", options.epochs);
    errdefer fitting.fail("CSV training failed");
    for (0..options.epochs) |epoch| {
        const loss = try model.trainBatch(training, 0.05, .cross_entropy);
        if (epoch % 64 == 0 or epoch + 1 == options.epochs) fitting.update(epoch + 1, &.{ .{ .name = "loss", .value = loss }, .{ .name = "epoch", .value = @floatFromInt(epoch + 1) } });
    }
    fitting.finish();
    const evaluation = try model.evaluateObserved(testing, .mse, observer);
    const q = try z.export_model.QuantizedFormat(S, if (options.int4) .int4 else .int8).calibrateObserved(&model, training, observer);
    var evaluating = observer.task("Quantized evaluation", testing.len);
    errdefer evaluating.fail("quantized evaluation failed");
    var correct: usize = 0;
    for (testing, 0..) |sample, index| {
        var input: [S.input_len]i8 = undefined;
        for (&input, sample.input) |*v, f| v.* = try z.export_model.quantizeInput(f, q.scales[0]);
        const output = q.infer(&input);
        var target: usize = 0;
        for (sample.target, 0..) |v, i| {
            if (v > sample.target[target]) target = i;
        }
        correct += @intFromBool(z.argmax(&output).? == target);
        if (index % 256 == 0 or index + 1 == testing.len) evaluating.update(index + 1, &.{});
    }
    evaluating.finish();
    const bytes = model.encode();
    try std.Io.Dir.cwd().writeFile(init.io, .{ .sub_path = args[3], .data = &bytes });
    var source: std.Io.Writer.Allocating = .init(a);
    var exporting = observer.task("Source export", null);
    errdefer exporting.fail("source export failed");
    try q.writeSource(&source.writer);
    try q.writeVerification(&source.writer, testing[0..@min(16, testing.len)]);
    try std.Io.Dir.cwd().writeFile(init.io, .{ .sub_path = args[4], .data = source.written() });
    exporting.finish();
    const message = try std.fmt.allocPrint(a, "CSV: train={d} test={d} float={d}/{d} quantized={d}/{d}; saved {s} and {s}\n", .{ training.len, testing.len, evaluation.correct, testing.len, correct, testing.len, args[3], args[4] });
    try std.Io.File.stdout().writeStreamingAll(init.io, message);
}
