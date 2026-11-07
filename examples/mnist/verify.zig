const std = @import("std");
const z = @import("zinn");
const m = @import("trained_model");
const options = @import("dataset_options");
const dataset = @import("dataset.zig");
const S = @import("definition.zig").Structure(options.cnn);
const T = z.Trainer(S);
pub fn main(init: std.process.Init) !void {
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    if (args.len != 8) return error.ExpectedCheckpointAndDatasetPaths;
    if (m.schema_tag != S.schema_tag) return error.DefinitionMismatch;
    var model = T.init(42);
    try model.decode(try dataset.read(init, args[1]));
    const calibration = try dataset.load(T, init, args[2], args[3], try std.fmt.parseInt(usize, args[6], 10));
    const samples = try dataset.load(T, init, args[4], args[5], try std.fmt.parseInt(usize, args[7], 10));
    const reference = try z.export_model.QuantizedFormat(S, if (options.int4) .int4 else .int8).calibrate(&model, calibration);
    var ws: m.Model.Workspace = undefined;
    for (samples) |sample| {
        var input: [S.input_len]i8 = undefined;
        for (&input, sample.input) |*v, f| v.* = try z.export_model.quantizeInput(f, m.input_scale);
        var output: [S.output_len]i8 = undefined;
        m.Model.infer(&input, &output, &ws);
        const expected = reference.infer(&input);
        if (!std.mem.eql(i8, &output, &expected)) return error.MnistIntegerReferenceMismatch;
    }
    std.debug.print("MNIST generated core: {d}/{d} exact reference matches; parameters={d}B workspace={d}B\n", .{ samples.len, samples.len, m.Model.parameter_bytes, m.Model.workspace_bytes });
}
