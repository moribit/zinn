//! Host-only float32 SGD training; inference does not import this module.
const std = @import("std");
const spatial = @import("spatial.zig");
pub const Evaluation = struct { loss: f32, correct: usize };
pub const Loss = enum { mse, cross_entropy };
pub fn checksum(data: []const u8) u64 {
    var result: u64 = 14695981039346656037;
    for (data) |byte| result = (result ^ byte) *% 1099511628211;
    return result;
}
pub fn Trainer(comptime S: type) type {
    return struct {
        const Self = @This();
        pub const Sample = struct { input: [S.input_len]f32, target: [S.output_len]f32 };
        pub const checkpoint_len = 32 + S.parameter_count * 4 + 8;
        parameters: [S.parameter_count]f32,
        seed: u32,
        epochs: u32 = 0,
        pub fn init(seed: u32) Self {
            var self: Self = .{ .parameters = undefined, .seed = seed };
            var rng = seed;
            inline for (S.layers, 0..) |_, l| {
                const n = S.fanins[l];
                const base = S.offsets[l];
                for (0..S.weight_counts[l]) |i| {
                    rng = rng *% 1664525 +% 1013904223;
                    self.parameters[base + i] = (@as(f32, @floatFromInt(rng >> 8)) / 16777216.0 * 2 - 1) * @sqrt(2.0 / @as(f32, @floatFromInt(n)));
                }
                @memset(self.parameters[base + S.weight_counts[l] ..][0..S.bias_counts[l]], 0.1);
            }
            return self;
        }
        pub const Activations = [S.layer_count + 1][S.max_width]f32;
        pub fn forward(self: *const Self, input: *const [S.input_len]f32, activations: *Activations) void {
            @memcpy(activations[0][0..S.input_len], input);
            inline for (S.layers, 0..) |layer, l| {
                const base = S.offsets[l];
                for (0..S.widths[l + 1]) |o| {
                    var sum: f32 = if (layer.kind == .average_pool2d) 0 else self.parameters[base + S.weight_counts[l] + spatial.biasIndex(S, l, o)];
                    for (0..S.fanins[l]) |k| {
                        if (spatial.inputIndex(S, l, o, k)) |i| {
                            const weight: f32 = if (layer.kind == .average_pool2d) 1.0 / @as(f32, @floatFromInt(S.fanins[l])) else self.parameters[base + spatial.weightIndex(S, l, o, k)];
                            sum += weight * activations[l][i];
                        }
                    }
                    activations[l + 1][o] = if (layer.activation == .relu) @max(0, sum) else sum;
                }
            }
        }
        pub fn predict(self: *const Self, input: *const [S.input_len]f32) [S.output_len]f32 {
            var a: Activations = undefined;
            self.forward(input, &a);
            return a[S.layer_count][0..S.output_len].*;
        }
        /// Mean squared error, averaged over outputs; gradient in parameter order.
        pub fn gradient(self: *const Self, sample: Sample, result: *[S.parameter_count]f32) f32 {
            return self.gradientWithLoss(sample, result, .mse);
        }
        pub fn gradientWithLoss(self: *const Self, sample: Sample, result: *[S.parameter_count]f32, loss_kind: Loss) f32 {
            @memset(result, 0);
            var a: Activations = undefined;
            self.forward(&sample.input, &a);
            var delta: [S.layer_count][S.max_width]f32 = undefined;
            var loss: f32 = 0;
            if (loss_kind == .cross_entropy) {
                var maximum: f32 = -std.math.inf(f32);
                for (a[S.layer_count][0..S.output_len]) |v| maximum = @max(maximum, v);
                var sum: f32 = 0;
                for (a[S.layer_count][0..S.output_len]) |v| sum += @exp(v - maximum);
                const log_sum = @log(sum);
                for (0..S.output_len) |o| {
                    const log_probability = a[S.layer_count][o] - maximum - log_sum;
                    loss -= sample.target[o] * log_probability;
                    delta[S.layer_count - 1][o] = @exp(log_probability) - sample.target[o];
                }
            } else for (0..S.output_len) |o| {
                const diff = a[S.layer_count][o] - sample.target[o];
                loss += diff * diff / @as(f32, @floatFromInt(S.output_len));
                delta[S.layer_count - 1][o] = 2 * diff / @as(f32, @floatFromInt(S.output_len));
            }
            inline for (0..S.layer_count) |reverse| {
                const l = S.layer_count - 1 - reverse;
                const layer = S.layers[l];
                const base = S.offsets[l];
                if (l > 0) @memset(delta[l - 1][0..S.widths[l]], 0);
                for (0..S.widths[l + 1]) |o| {
                    const d = if (layer.activation == .relu and a[l + 1][o] <= 0) 0 else delta[l][o];
                    if (layer.kind != .average_pool2d) result[base + S.weight_counts[l] + spatial.biasIndex(S, l, o)] += d;
                    for (0..S.fanins[l]) |k| {
                        if (spatial.inputIndex(S, l, o, k)) |i| {
                            const wi = base + spatial.weightIndex(S, l, o, k);
                            const weight: f32 = if (layer.kind == .average_pool2d) 1.0 / @as(f32, @floatFromInt(S.fanins[l])) else self.parameters[wi];
                            if (layer.kind != .average_pool2d) result[wi] += d * a[l][i];
                            if (l > 0) delta[l - 1][i] += d * weight;
                        }
                    }
                }
            }
            return loss;
        }
        pub fn trainEpoch(self: *Self, samples: []const Sample, rate: f32) !f32 {
            return self.trainBatch(samples, rate, .mse);
        }
        pub fn trainBatch(self: *Self, samples: []const Sample, rate: f32, loss_kind: Loss) !f32 {
            if (loss_kind == .cross_entropy and S.layers[S.layer_count - 1].activation != .none) return error.CrossEntropyRequiresLogits;
            if (samples.len == 0 or !std.math.isFinite(rate) or rate <= 0) return error.InvalidTrainingOptions;
            var total: [S.parameter_count]f32 = @splat(0);
            var loss: f32 = 0;
            for (samples) |sample| {
                for (sample.input) |value| if (!std.math.isFinite(value)) return error.NonFiniteInput;
                for (sample.target) |value| if (!std.math.isFinite(value)) return error.NonFiniteInput;
                var gradient_values: [S.parameter_count]f32 = undefined;
                if (loss_kind == .cross_entropy) {
                    var target_sum: f32 = 0;
                    for (sample.target) |v| {
                        if (v < 0) return error.InvalidClassTarget;
                        target_sum += v;
                    }
                    if (@abs(target_sum - 1) > 0.0001) return error.InvalidClassTarget;
                }
                loss += self.gradientWithLoss(sample, &gradient_values, loss_kind);
                for (&total, gradient_values) |*sum, g| sum.* += g;
            }
            var next = self.parameters;
            for (&next, total) |*p, g| {
                p.* -= rate * g / @as(f32, @floatFromInt(samples.len));
                if (!std.math.isFinite(p.*)) return error.NonFiniteParameters;
            }
            if (!std.math.isFinite(loss)) return error.NonFiniteLoss;
            self.parameters = next;
            self.epochs += 1;
            return loss / @as(f32, @floatFromInt(samples.len));
        }
        pub fn evaluate(self: *const Self, samples: []const Sample) !Evaluation {
            return self.evaluateWithLoss(samples, .mse);
        }
        pub fn evaluateWithLoss(self: *const Self, samples: []const Sample, loss_kind: Loss) !Evaluation {
            if (samples.len == 0) return error.EmptyDataset;
            for (self.parameters) |value| if (!std.math.isFinite(value)) return error.NonFiniteParameters;
            var loss: f32 = 0;
            var correct: usize = 0;
            for (samples) |sample| {
                for (sample.input) |value| if (!std.math.isFinite(value)) return error.NonFiniteInput;
                const prediction = self.predict(&sample.input);
                var predicted: usize = 0;
                var target: usize = 0;
                var maximum: f32 = -std.math.inf(f32);
                for (prediction) |v| maximum = @max(maximum, v);
                var exp_sum: f32 = 0;
                if (loss_kind == .cross_entropy) for (prediction) |v| {
                    exp_sum += @exp(v - maximum);
                };
                for (prediction, 0..) |value, i| {
                    if (!std.math.isFinite(value) or !std.math.isFinite(sample.target[i])) return error.NonFiniteEvaluation;
                    if (value > prediction[predicted]) predicted = i;
                    if (sample.target[i] > sample.target[target]) target = i;
                    const d = value - sample.target[i];
                    loss += if (loss_kind == .mse) d * d / @as(f32, @floatFromInt(S.output_len)) else -sample.target[i] * (value - maximum - @log(exp_sum));
                }
                correct += @intFromBool(predicted == target);
            }
            if (!std.math.isFinite(loss)) return error.NonFiniteEvaluation;
            return .{ .loss = loss / @as(f32, @floatFromInt(samples.len)), .correct = correct };
        }
        pub fn encode(self: *const Self) [checkpoint_len]u8 {
            var bytes: [checkpoint_len]u8 = @splat(0);
            @memcpy(bytes[0..8], "ZINNf32\x01");
            std.mem.writeInt(u64, bytes[8..16], S.schema_tag, .little);
            std.mem.writeInt(u32, bytes[16..20], self.seed, .little);
            std.mem.writeInt(u32, bytes[20..24], self.epochs, .little);
            for (self.parameters, 0..) |p, i| std.mem.writeInt(u32, bytes[32 + i * 4 ..][0..4], @bitCast(p), .little);
            std.mem.writeInt(u64, bytes[checkpoint_len - 8 ..], checksum(bytes[0 .. checkpoint_len - 8]), .little);
            return bytes;
        }
        pub fn decode(self: *Self, bytes: []const u8) !void {
            if (bytes.len != checkpoint_len or !std.mem.eql(u8, bytes[0..8], "ZINNf32\x01")) return error.InvalidCheckpoint;
            if (std.mem.readInt(u64, bytes[8..16], .little) != S.schema_tag) return error.CheckpointSchemaMismatch;
            if (std.mem.readInt(u64, bytes[checkpoint_len - 8 ..][0..8], .little) != checksum(bytes[0 .. checkpoint_len - 8])) return error.CheckpointChecksumMismatch;
            var next = self.*;
            for (&next.parameters, 0..) |*p, i| {
                p.* = @bitCast(std.mem.readInt(u32, bytes[32 + i * 4 ..][0..4], .little));
                if (!std.math.isFinite(p.*)) return error.NonFiniteParameters;
            }
            next.seed = std.mem.readInt(u32, bytes[16..20], .little);
            next.epochs = std.mem.readInt(u32, bytes[20..24], .little);
            self.* = next;
        }
    };
}
