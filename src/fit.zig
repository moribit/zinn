//! Explicit host-only dataset split and mini-batch training. Checkpoint v1 is unchanged.
const std = @import("std");
const progress = @import("host/progress.zig");
pub const Options = struct { epochs: usize = 20, batch: usize = 32, rate: f32 = 0.05, seed: u32 = 42, decay_every: usize = 10, decay: f32 = 0.3, observer: progress.Observer = .{}, model_name: []const u8 = "training" };
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
    const batches = 1 + (training.len - 1) / options.batch;
    const total = std.math.mul(u64, batches, options.epochs) catch return error.InvalidTrainingOptions;
    var task = options.observer.task(options.model_name, total);
    task.unit = "batches";
    errdefer task.fail("operation failed");
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
        while (start < training.len) : (start += options.batch) {
            const loss = try model.trainBatch(training[start..@min(start + options.batch, training.len)], rate, .cross_entropy);
            if (options.observer.callback != null) task.update(epoch * batches + start / options.batch + 1, &.{ .{ .name = "epoch", .value = @floatFromInt(epoch + 1) }, .{ .name = "epochs", .value = @floatFromInt(options.epochs) }, .{ .name = "batch", .value = @floatFromInt(start / options.batch + 1) }, .{ .name = "batches", .value = @floatFromInt(batches) }, .{ .name = "loss", .value = loss }, .{ .name = "lr", .value = rate } });
        }
        const train_score = try model.evaluateWithLoss(training, .cross_entropy);
        const score = if (validation.len > 0) try model.evaluateWithLoss(validation, .cross_entropy) else train_score;
        try curve.print("{d},{d},{d},{d},{d},{d},{d},{d}\n", .{ epoch + 1, rate, train_score.loss, train_score.correct, training.len, score.loss, score.correct, validation.len });
        const improved = validation.len == 0 or result.best_epoch == 0 or score.correct > result.best_validation_correct or (score.correct == result.best_validation_correct and score.loss < result.best_validation_loss);
        if (improved) {
            best = model.*;
            result.best_epoch = epoch + 1;
            result.best_validation_correct = score.correct;
            result.best_validation_loss = score.loss;
        }
        options.observer.emit(.{ .name = options.model_name, .kind = .epoch, .unit = "batches", .done = (epoch + 1) * batches, .total = total, .metrics = &.{ .{ .name = "epoch", .value = @floatFromInt(epoch + 1) }, .{ .name = "epochs", .value = @floatFromInt(options.epochs) }, .{ .name = "loss", .value = train_score.loss }, .{ .name = "lr", .value = rate }, .{ .name = if (validation.len > 0) "val_acc" else "train_acc", .value = 100 * @as(f64, @floatFromInt(score.correct)) / @as(f64, @floatFromInt(if (validation.len > 0) validation.len else training.len)) }, .{ .name = if (validation.len > 0) "val_loss" else "train_loss", .value = score.loss }, .{ .name = "best", .value = if (improved) 1 else 0 } } });
    }
    model.* = best;
    task.done = total;
    task.finishWithMetrics(&.{ .{ .name = "selected_epoch", .value = @floatFromInt(result.best_epoch) }, .{ .name = if (validation.len > 0) "best_val_acc" else "final_train_acc", .value = 100 * @as(f64, @floatFromInt(result.best_validation_correct)) / @as(f64, @floatFromInt(if (validation.len > 0) validation.len else training.len)) }, .{ .name = if (validation.len > 0) "best_val_loss" else "final_train_loss", .value = result.best_validation_loss } });
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
test "observation does not change updates, selection, curve or checkpoint" {
    const T = @import("train.zig").Trainer(@import("definition.zig").Definition(2, &.{ .{ .units = 4, .activation = .relu }, .{ .units = 2 } }));
    const initial = [_]T.Sample{ .{ .input = .{ 0, 0 }, .target = .{ 1, 0 } }, .{ .input = .{ 0, 1 }, .target = .{ 0, 1 } }, .{ .input = .{ 1, 0 }, .target = .{ 0, 1 } }, .{ .input = .{ 1, 1 }, .target = .{ 1, 0 } } };
    var first = initial;
    var second = initial;
    var a = T.init(42);
    var b = a;
    var curve_a: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer curve_a.deinit();
    var curve_b: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer curve_b.deinit();
    const Capture = struct {
        batches: usize = 0,
        epochs: usize = 0,
        best: usize = 0,
        failed: bool = false,
        fn event(context: ?*anyopaque, e: progress.Event) void {
            const self: *@This() = @ptrCast(@alignCast(context.?));
            if (e.kind == .updated) self.batches += 1;
            if (e.kind == .epoch) {
                self.epochs += 1;
                for (e.metrics) |m| if (std.mem.eql(u8, m.name, "best") and m.value == 1) {
                    self.best += 1;
                };
            }
            if (e.kind == .failed) self.failed = true;
        }
    };
    var capture: Capture = .{};
    _ = try train(T, &a, &first, initial[0..2], .{ .epochs = 12, .batch = 3, .decay_every = 4 }, &curve_a.writer);
    _ = try train(T, &b, &second, initial[0..2], .{ .epochs = 12, .batch = 3, .decay_every = 4, .observer = .{ .context = &capture, .callback = Capture.event } }, &curve_b.writer);
    try std.testing.expectEqualSlices(u8, &a.encode(), &b.encode());
    try std.testing.expectEqualSlices(u8, curve_a.written(), curve_b.written());
    try std.testing.expectEqual(@as(usize, 24), capture.batches);
    try std.testing.expectEqual(@as(usize, 12), capture.epochs);
    try std.testing.expect(capture.best > 0);
    try std.testing.expect(!capture.failed);
    var bad: [1]T.Sample = .{.{ .input = .{ std.math.nan(f32), 0 }, .target = .{ 1, 0 } }};
    try std.testing.expectError(error.NonFiniteInput, train(T, &b, &bad, &.{}, .{ .epochs = 1, .observer = .{ .context = &capture, .callback = Capture.event } }, &curve_b.writer));
    try std.testing.expect(capture.failed);
}
