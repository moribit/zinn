const std = @import("std");
const z = @import("zinn");
const options = @import("dataset_options");
const S = @import("definition.zig").Structure(options.cnn);
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
    const args = try init.minimal.args.toSlice(init.arena.allocator());
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
        const samples = try load(init, args[2], args[3], try number(usize, args[5]));
        try log(init, "seed={d} epochs={d} minibatch={d} learning_rate={d} train_count={d} preprocessing=area28to16_div255\n", .{ seed, epochs, batch, rate, samples.len });
        var rng = seed;
        for (0..epochs) |epoch| {
            var i = samples.len;
            while (i > 1) {
                i -= 1;
                rng = rng *% 1664525 +% 1013904223;
                std.mem.swap(T.Sample, &samples[i], &samples[rng % (i + 1)]);
            }
            var start: usize = 0;
            var loss: f64 = 0;
            while (start < samples.len) : (start += batch) {
                const chunk = samples[start..@min(start + batch, samples.len)];
                loss += @as(f64, try model.trainBatch(chunk, rate, .cross_entropy)) * @as(f64, @floatFromInt(chunk.len));
            }
            try log(init, "MNIST {s}: epoch={d}/{d} train={d} CE={d:.6}\n", .{ if (options.cnn) "cnn" else "mlp", epoch + 1, epochs, samples.len, loss / @as(f64, @floatFromInt(samples.len)) });
        }
        // Checkpoint epochs historically counts optimizer steps; preserve that contract.
        const bytes = model.encode();
        try std.Io.Dir.cwd().writeFile(init.io, .{ .sub_path = args[9], .data = &bytes });
    } else if (std.mem.eql(u8, args[1], "export")) {
        if (args.len != 11) return error.ExpectedExportArguments;
        try model.decode(try read(init, args[2]));
        if (std.mem.eql(u8, args[3], args[5]) or std.mem.eql(u8, args[4], args[6])) return error.TrainTestPathsMustDiffer;
        const calibration = try load(init, args[3], args[4], try number(usize, args[7]));
        const testing = try load(init, args[5], args[6], try number(usize, args[8]));
        const quantized = try Q.calibrate(&model, calibration);
        const evaluation = try model.evaluate(testing);
        var correct: usize = 0;
        var max_logit_error: f32 = 0;
        for (testing) |sample| {
            const output = quantized.infer(&try encodeInput(sample, quantized.scales[0]));
            correct += @intFromBool(z.argmax(&output).? == class(sample.target));
            const floating = model.predict(&sample.input);
            for (output, floating) |integer, f| max_logit_error = @max(max_logit_error, @abs(@as(f32, @floatFromInt(integer)) * quantized.scales[S.layer_count] - f));
        }
        const report = try std.fmt.allocPrint(init.arena.allocator(), "dataset={s} architecture={s} weights={s} seed={d} optimizer_steps={d} calibration_train_only={d} held_out_test={d} float_correct={d} float_accuracy={d:.4}% quantized_correct={d} quantized_accuracy={d:.4}% max_logit_error={d:.6}\n", .{ if (options.fixture) "synthetic-fixture" else "MNIST", if (options.cnn) "cnn" else "mlp", if (options.int4) "int4" else "int8", model.seed, model.epochs, calibration.len, testing.len, evaluation.correct, 100 * @as(f64, @floatFromInt(evaluation.correct)) / @as(f64, @floatFromInt(testing.len)), correct, 100 * @as(f64, @floatFromInt(correct)) / @as(f64, @floatFromInt(testing.len)), max_logit_error });
        try std.Io.File.stdout().writeStreamingAll(init.io, report);
        try std.Io.Dir.cwd().writeFile(init.io, .{ .sub_path = args[10], .data = report });
        var source: std.Io.Writer.Allocating = .init(init.arena.allocator());
        try quantized.writeSource(&source.writer);
        const count = @min(16, testing.len);
        try quantized.writeVerification(&source.writer, testing[0..count]);
        try std.Io.Dir.cwd().writeFile(init.io, .{ .sub_path = args[9], .data = source.written() });
    } else return error.UnknownCommand;
}
