//! Explicit host-only dataset split and mini-batch training. Checkpoint v1 is unchanged.
const std = @import("std");
pub const Options = struct { epochs: usize = 20, batch: usize = 32, rate: f32 = 0.05, seed: u32 = 42, decay_every: usize = 10, decay: f32 = 0.3 };
pub fn split(comptime Sample: type, samples: []Sample, validation_count: usize, seed: u32) !struct { training: []Sample, validation: []const Sample } {
    if (samples.len == 0 or validation_count >= samples.len) return error.InvalidValidationCount;
    if (validation_count > 0) {
        var rng = seed;
        var i = samples.len;
        while (i > 1) {
            i -= 1;
            rng = rng *% 1664525 +% 1013904223;
            std.mem.swap(Sample, &samples[i], &samples[rng % (i + 1)]);
        }
    }
    return .{ .training = samples[0 .. samples.len - validation_count], .validation = samples[samples.len - validation_count ..] };
}
pub const Result = struct { best_epoch: usize, best_validation_correct: usize, validation_count: usize, training_count: usize, best_validation_loss: f32 };
pub fn train(comptime T: type, model: *T, training: []T.Sample, validation: []const T.Sample, options: Options, curve: *std.Io.Writer) !Result {
    if (options.epochs == 0 or options.batch == 0 or !std.math.isFinite(options.rate) or options.rate <= 0 or !std.math.isFinite(options.decay) or options.decay <= 0 or options.decay > 1 or training.len == 0) return error.InvalidTrainingOptions;
    var best = model.*;
    var result: Result = .{ .best_epoch = 0, .best_validation_correct = 0, .best_validation_loss = std.math.inf(f32), .training_count = training.len, .validation_count = validation.len };
    var rng = options.seed;
    var rate = options.rate;
    try curve.writeAll("epoch,learning_rate,train_ce,train_correct,train_count,validation_ce,validation_correct,validation_count\n");
    for (0..options.epochs) |epoch| {
        if (epoch > 0 and options.decay_every > 0 and epoch % options.decay_every == 0) rate *= options.decay;
        if (!std.math.isFinite(rate) or rate <= 0) return error.LearningRateScheduleUnderflow;
        var i = training.len;
        while (i > 1) {
            i -= 1;
            rng = rng *% 1664525 +% 1013904223;
            std.mem.swap(T.Sample, &training[i], &training[rng % (i + 1)]);
        }
        var start: usize = 0;
        while (start < training.len) : (start += options.batch) _ = try model.trainBatch(training[start..@min(start + options.batch, training.len)], rate, .cross_entropy);
        const train_score = try model.evaluateWithLoss(training, .cross_entropy);
        const score = if (validation.len > 0) try model.evaluateWithLoss(validation, .cross_entropy) else train_score;
        try curve.print("{d},{d},{d},{d},{d},{d},{d},{d}\n", .{ epoch + 1, rate, train_score.loss, train_score.correct, training.len, score.loss, score.correct, validation.len });
        if (validation.len == 0 or result.best_epoch == 0 or score.correct > result.best_validation_correct or (score.correct == result.best_validation_correct and score.loss < result.best_validation_loss)) {
            best = model.*;
            result.best_epoch = epoch + 1;
            result.best_validation_correct = score.correct;
            result.best_validation_loss = score.loss;
        }
    }
    model.* = best;
    return result;
}
test "split is deterministic and training never writes validation or invalid options" {
    const T = @import("train.zig").Trainer(@import("definition.zig").Definition(1, &.{.{ .units = 2 }}));
    var a = [_]T.Sample{ .{ .input = .{0}, .target = .{ 1, 0 } }, .{ .input = .{1}, .target = .{ 0, 1 } }, .{ .input = .{2}, .target = .{ 0, 1 } }, .{ .input = .{3}, .target = .{ 0, 1 } } };
    var b = a;
    const first = try split(T.Sample, &a, 1, 123);
    const second = try split(T.Sample, &b, 1, 123);
    try std.testing.expectEqualSlices(u8, std.mem.sliceAsBytes(first.validation), std.mem.sliceAsBytes(second.validation));
    const held = first.validation[0];
    var model = T.init(4);
    var curve: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer curve.deinit();
    _ = try train(T, &model, first.training, first.validation, .{ .epochs = 2, .batch = 2 }, &curve.writer);
    try std.testing.expectEqualSlices(f32, &held.input, &first.validation[0].input);
    try std.testing.expectError(error.InvalidTrainingOptions, train(T, &model, first.training, first.validation, .{ .epochs = 0 }, &curve.writer));
    try std.testing.expectError(error.InvalidValidationCount, split(T.Sample, &a, 4, 1));
}
