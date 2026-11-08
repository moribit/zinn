const std = @import("std");
const z = @import("zinn");
const m = @import("trained_model");
const options = @import("dataset_options");
const dataset = @import("dataset.zig");
const S = @import("project_model").Structure;
const T = z.Trainer(S);
pub fn main(init: std.process.Init) !void {
    const parsed = try z.host.progress.cli(init);
    const args = parsed.args;
    var renderer = z.host.progress.Renderer.init(init, parsed.mode);
    defer renderer.deinit();
    const observer = renderer.observer();
    var task = observer.task("Integer reference verification", null);
    errdefer task.fail("reference verification failed");
    if (args.len != 8) return error.ExpectedCheckpointAndDatasetPaths;
    if (m.schema_tag != S.schema_tag) return error.DefinitionMismatch;
    var model = T.init(42);
    try model.decode(try dataset.read(init, args[1]));
    const all_train = try dataset.load(T, init, args[2], args[3], options.train_limit);
    const partitions = try dataset.partition(T, all_train);
    const calibration = partitions.training[0..@min(try std.fmt.parseInt(usize, args[6], 10), partitions.training.len)];
    const samples = if (options.evaluation_test) try dataset.load(T, init, args[4], args[5], try std.fmt.parseInt(usize, args[7], 10)) else partitions.validation[0..@min(try std.fmt.parseInt(usize, args[7], 10), partitions.validation.len)];
    const reference = try z.export_model.QuantizedFormat(S, if (options.int4) .int4 else .int8).calibrate(&model, calibration);
    var ws: m.Model.Workspace = undefined;
    task.total = samples.len;
    for (samples, 0..) |sample, index| {
        var input: [S.input_len]i8 = undefined;
        for (&input, sample.input) |*v, f| v.* = try z.export_model.quantizeInput(f, m.input_scale);
        var output: [S.output_len]i8 = undefined;
        m.Model.infer(&input, &output, &ws);
        const expected = reference.infer(&input);
        if (!std.mem.eql(i8, &output, &expected)) return error.MnistIntegerReferenceMismatch;
        if (index % 256 == 0 or index + 1 == samples.len) task.update(index + 1, &.{});
    }
    task.finish();
    std.debug.print("MNIST generated core: {d}/{d} exact reference matches; parameters={d}B workspace={d}B\n", .{ samples.len, samples.len, m.Model.parameter_bytes, m.Model.workspace_bytes });
}
