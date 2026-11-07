const std = @import("std");
const z = @import("zinn");
const d = @import("definition.zig");
fn log(init: std.process.Init, comptime fmt: []const u8, args: anytype) !void {
    const message = try std.fmt.allocPrint(init.arena.allocator(), fmt, args);
    try std.Io.File.stdout().writeStreamingAll(init.io, message);
}
pub fn main(init: std.process.Init) !void {
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    if (args.len < 3) return error.ExpectedCommandAndPath;
    var model = d.Training.init(42);
    if (std.mem.eql(u8, args[1], "train")) {
        for (0..10000) |_| _ = try model.trainEpoch(&d.samples, 0.05);
        const evaluation = try model.evaluate(&d.samples);
        if (evaluation.correct != 4 or evaluation.loss > 0.001) return error.TrainingDidNotConverge;
        const bytes = model.encode();
        try std.Io.Dir.cwd().writeFile(init.io, .{ .sub_path = args[2], .data = &bytes });
        try log(init, "train: seed={d} epochs={d} MSE={e} correct={d}/4 checkpoint={s}\n", .{ model.seed, model.epochs, evaluation.loss, evaluation.correct, args[2] });
    } else {
        const bytes = try std.Io.Dir.cwd().readFileAlloc(init.io, args[2], init.arena.allocator(), .limited(1024 * 1024));
        try model.decode(bytes);
        const evaluation = try model.evaluate(&d.samples);
        if (std.mem.eql(u8, args[1], "eval")) {
            try log(init, "eval: MSE={e} correct={d}/4 (XOR truth table, not held-out accuracy)\n", .{ evaluation.loss, evaluation.correct });
            if (evaluation.correct != 4) return error.EvaluationFailed;
        } else if (std.mem.eql(u8, args[1], "quantize")) {
            if (args.len != 4) return error.ExpectedSourceOutput;
            const quantized = try z.export_model.QuantizedFormat(d.Structure, if (@import("dataset_options").int4) .int4 else .int8).calibrate(&model, &d.samples);
            var output: std.Io.Writer.Allocating = .init(init.arena.allocator());
            try quantized.writeSource(&output.writer);
            // Golden vectors are produced by the independently accumulated host reference.
            try output.writer.writeAll("pub const inputs = [4][2]i8{\n");
            for (d.samples) |sample| {
                try output.writer.print(".{{{d},{d}}},\n", .{ try z.export_model.quantizeInput(sample.input[0], quantized.scales[0]), try z.export_model.quantizeInput(sample.input[1], quantized.scales[0]) });
            }
            try output.writer.writeAll("};\npub const expected = [4][2]i8{\n");
            for (d.samples) |sample| {
                const input = [2]i8{ try z.export_model.quantizeInput(sample.input[0], quantized.scales[0]), try z.export_model.quantizeInput(sample.input[1], quantized.scales[0]) };
                const prediction = quantized.infer(&input);
                const target: usize = if (sample.target[0] > sample.target[1]) 0 else 1;
                if (z.argmax(&prediction).? != target) return error.QuantizedAccuracyRegression;
                try output.writer.print(".{{{d},{d}}},\n", .{ prediction[0], prediction[1] });
            }
            try output.writer.writeAll("};\n");
            try std.Io.Dir.cwd().writeFile(init.io, .{ .sub_path = args[3], .data = output.written() });
            try log(init, "quantize: int8 reference 4/4; source={s}\n", .{args[3]});
        } else return error.UnknownCommand;
    }
}
