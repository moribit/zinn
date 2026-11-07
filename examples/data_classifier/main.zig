const std = @import("std");
const z = @import("zinn");
const options = @import("csv_options");
const S = z.Definition(options.features, &.{ .{ .units = options.hidden, .activation = .relu }, .{ .units = options.classes } });
const T = z.Trainer(S);
pub fn main(init: std.process.Init) !void {
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    if (args.len != 5) return error.ExpectedTrainCsvTestCsvCheckpointSource;
    if (std.mem.eql(u8, args[1], args[2])) return error.TrainTestPathsMustDiffer;
    const a = init.arena.allocator();
    const train_text = try std.Io.Dir.cwd().readFileAlloc(init.io, args[1], a, .limited(64 * 1024 * 1024));
    const test_text = try std.Io.Dir.cwd().readFileAlloc(init.io, args[2], a, .limited(64 * 1024 * 1024));
    const training = try z.data.csv(T, a, train_text, options.header);
    const testing = try z.data.csv(T, a, test_text, options.header);
    var model = T.init(42);
    for (0..options.epochs) |_| {
        _ = try model.trainBatch(training, 0.05, .cross_entropy);
    }
    const evaluation = try model.evaluate(testing);
    const q = try z.export_model.QuantizedFormat(S, if (options.int4) .int4 else .int8).calibrate(&model, training);
    var correct: usize = 0;
    for (testing) |sample| {
        var input: [S.input_len]i8 = undefined;
        for (&input, sample.input) |*v, f| v.* = try z.export_model.quantizeInput(f, q.scales[0]);
        const output = q.infer(&input);
        var target: usize = 0;
        for (sample.target, 0..) |v, i| {
            if (v > sample.target[target]) target = i;
        }
        correct += @intFromBool(z.argmax(&output).? == target);
    }
    const bytes = model.encode();
    try std.Io.Dir.cwd().writeFile(init.io, .{ .sub_path = args[3], .data = &bytes });
    var source: std.Io.Writer.Allocating = .init(a);
    try q.writeSource(&source.writer);
    try q.writeVerification(&source.writer, testing[0..@min(16, testing.len)]);
    try std.Io.Dir.cwd().writeFile(init.io, .{ .sub_path = args[4], .data = source.written() });
    const message = try std.fmt.allocPrint(a, "CSV: train={d} test={d} float={d}/{d} quantized={d}/{d}; saved {s} and {s}\n", .{ training.len, testing.len, evaluation.correct, testing.len, correct, testing.len, args[3], args[4] });
    try std.Io.File.stdout().writeStreamingAll(init.io, message);
}
