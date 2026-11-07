const std = @import("std");
const z = @import("root.zig");
const S = z.Definition(2, &.{ .{ .units = 8, .activation = .relu }, .{ .units = 2 } });
const T = z.Trainer(S);
const samples = [_]T.Sample{
    .{ .input = .{ 0, 0 }, .target = .{ 1, 0 } }, .{ .input = .{ 0, 1 }, .target = .{ 0, 1 } },
    .{ .input = .{ 1, 0 }, .target = .{ 0, 1 } }, .{ .input = .{ 1, 1 }, .target = .{ 1, 0 } },
};
test "SGD XOR convergence, deterministic initialization, checkpoint roundtrip and rejection" {
    var model = T.init(42);
    var duplicate = T.init(42);
    for (0..10000) |_| {
        _ = try model.trainEpoch(&samples, 0.05);
        _ = try duplicate.trainEpoch(&samples, 0.05);
    }
    const evaluation = try model.evaluate(&samples);
    try std.testing.expectEqual(@as(usize, 4), evaluation.correct);
    try std.testing.expect(evaluation.loss < 0.001);
    try std.testing.expectEqualSlices(f32, &model.parameters, &duplicate.parameters);
    var bytes = model.encode();
    var loaded = T.init(7);
    try loaded.decode(&bytes);
    try std.testing.expectEqualSlices(f32, &model.parameters, &loaded.parameters);
    try std.testing.expectEqual(model.epochs, loaded.epochs);
    bytes[33] ^= 1;
    try std.testing.expectError(error.CheckpointChecksumMismatch, loaded.decode(&bytes));
    try std.testing.expectEqualSlices(f32, &model.parameters, &loaded.parameters);
    try std.testing.expectError(error.InvalidCheckpoint, loaded.decode(bytes[0..12]));
    try std.testing.expectError(error.InvalidTrainingOptions, loaded.trainEpoch(&.{}, 0.05));
}
test "backpropagation agrees with finite difference for each parameter" {
    var model = T.init(42);
    var gradient: [S.parameter_count]f32 = undefined;
    _ = model.gradient(samples[1], &gradient);
    for (&model.parameters, 0..) |*parameter, i| {
        const old = parameter.*;
        parameter.* = old + 0.001;
        const plus = try model.evaluate(samples[1..2]);
        parameter.* = old - 0.001;
        const minus = try model.evaluate(samples[1..2]);
        parameter.* = old;
        try std.testing.expectApproxEqAbs(gradient[i], (plus.loss - minus.loss) / 0.002, 0.001);
    }
}

test "export calibration coefficients, input validation and deterministic source" {
    const exporter = @import("export.zig");
    try std.testing.expectError(error.InvalidScale, exporter.coefficient(0));
    try std.testing.expectError(error.UnrepresentableScale, exporter.coefficient(1e-30));
    try std.testing.expectError(error.InvalidScale, exporter.quantizeInput(std.math.nan(f32), 1));
    var model = T.init(42);
    try std.testing.expectError(error.EmptyCalibration, exporter.Quantized(S).calibrate(&model, &.{}));
    for (0..10000) |_| _ = try model.trainEpoch(&samples, 0.05);
    const quantized = try exporter.Quantized(S).calibrate(&model, &samples);
    var first: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer first.deinit();
    var second: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer second.deinit();
    try quantized.writeSource(&first.writer);
    var restored = T.init(7);
    const checkpoint = model.encode();
    try restored.decode(&checkpoint);
    const restored_quantized = try exporter.Quantized(S).calibrate(&restored, &samples);
    try restored_quantized.writeSource(&second.writer);
    try std.testing.expectEqualSlices(u8, first.written(), second.written());
    for (samples, 0..) |sample, i| {
        const input = [2]i8{ try exporter.quantizeInput(sample.input[0], quantized.scales[0]), try exporter.quantizeInput(sample.input[1], quantized.scales[0]) };
        const output = quantized.infer(&input);
        try std.testing.expectEqual(@as(?usize, if (i == 1 or i == 2) 1 else 0), z.argmax(&output));
    }
    model.parameters[0] = std.math.inf(f32);
    try std.testing.expectError(error.NonFiniteParameters, exporter.Quantized(S).calibrate(&model, &samples));
}
test "checkpoint rejects a different schema and nonfinite parameters transactionally" {
    var model = T.init(42);
    var bytes = model.encode();
    const old = model.parameters;
    bytes[8] ^= 1;
    try std.testing.expectError(error.CheckpointSchemaMismatch, model.decode(&bytes));
    bytes = model.encode();
    std.mem.writeInt(u32, bytes[32..36], @bitCast(std.math.nan(f32)), .little);
    std.mem.writeInt(u64, bytes[T.checkpoint_len - 8 ..], @import("train.zig").checksum(bytes[0 .. T.checkpoint_len - 8]), .little);
    try std.testing.expectError(error.NonFiniteParameters, model.decode(&bytes));
    try std.testing.expectEqualSlices(f32, &old, &model.parameters);
}

test "cross entropy is stable for large logits and rejects invalid targets without update" {
    const R = z.Trainer(z.Definition(1, &.{.{ .units = 2 }}));
    var model = R.init(1);
    model.parameters = .{ 0, 0, 1000, 999 };
    const sample: R.Sample = .{ .input = .{1}, .target = .{ 1, 0 } };
    var gradient: [4]f32 = undefined;
    const loss = model.gradientWithLoss(sample, &gradient, .cross_entropy);
    try std.testing.expectApproxEqAbs(@as(f32, 0.3132617), loss, 0.00001);
    try std.testing.expectApproxEqAbs(@as(f32, -0.2689414), gradient[2], 0.00001);
    const old = model.parameters;
    try std.testing.expectError(error.InvalidClassTarget, model.trainBatch(&.{.{ .input = .{1}, .target = .{ 1, 1 } }}, 0.1, .cross_entropy));
    try std.testing.expectEqualSlices(f32, &old, &model.parameters);
}
