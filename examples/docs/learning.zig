//! Executable numerical examples used by the bilingual introductory tutorials.
const std = @import("std");
const z = @import("zinn");
test "one neuron: forward, gradient and SGD" {
    const S = z.Definition(2, &.{.{ .units = 1 }});
    const T = z.Trainer(S);
    var model = T.init(42);
    model.parameters = .{ 0.5, -0.25, 0.1 };
    const sample: T.Sample = .{ .input = .{ 2, 2 }, .target = .{1} };
    var activations: T.Activations = undefined;
    model.forward(&sample.input, &activations);
    try std.testing.expectApproxEqAbs(@as(f32, 0.6), activations[1][0], 0.00001);
    var gradient: [S.parameter_count]f32 = undefined;
    const before = model.gradientWithLoss(sample, &gradient, .mse);
    try std.testing.expect(gradient[0] < 0);
    _ = try model.trainBatch(&.{sample}, 0.01, .mse);
    const after = model.gradientWithLoss(sample, &gradient, .mse);
    try std.testing.expect(after < before);
}
test "quantization rounding and terminal Bellman target" {
    try std.testing.expectEqual(@as(i8, 3), try z.export_model.quantizeInput(0.26, 0.1));
    try std.testing.expectEqual(@as(i8, 127), try z.export_model.quantizeInput(100, 0.1));
    try std.testing.expectEqual(@as(i8, -128), try z.export_model.quantizeInput(-100, 0.1));
    try std.testing.expectApproxEqAbs(@as(f32, 4.8), try z.rl.dqn.bellman(1, false, &.{ 2, 4 }, 0.95), 0.00001);
    try std.testing.expectEqual(@as(f32, 1), try z.rl.dqn.bellman(1, true, &.{ 2, 4 }, 0.95));
}
