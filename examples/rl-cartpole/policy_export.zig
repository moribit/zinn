//! Host-only CartPole export experiments. No changes to the shared exporter.
const std = @import("std");
const z = @import("zinn");
const a = @import("agent.zig");
comptime {
    if (!std.mem.eql(usize, &a.S.widths, &.{ 4, 16, 16, 2 })) @compileError("CartPole export strategies require the fixed 4-16-16-2 learner");
}
pub const Calibration = enum { baseline, representative, rollout, hybrid };
pub const Strategy = enum { centered, difference };
pub const Difference = z.Definition(4, &.{ .{ .units = 16, .activation = .relu }, .{ .units = 16, .activation = .relu }, .{ .units = 1 } });
pub fn difference(model: *const a.T) z.Trainer(Difference) {
    var result = z.Trainer(Difference).init(model.seed);
    const base = a.S.offsets[2];
    @memcpy(result.parameters[0..base], model.parameters[0..base]);
    for (0..16) |i| result.parameters[base + i] = model.parameters[base + 16 + i] - model.parameters[base + i];
    result.parameters[base + 16] = model.parameters[base + 33] - model.parameters[base + 32];
    result.epochs = model.epochs;
    return result;
}
pub fn samples(allocator: std.mem.Allocator, kind: Calibration, model: *const a.T, baseline: []const a.T.Sample) ![]a.T.Sample {
    if (baseline.len == 0) return error.EmptyCalibration;
    if (kind == .baseline) return allocator.dupe(a.T.Sample, baseline);
    const result = try allocator.alloc(a.T.Sample, 2049);
    var rng = z.rl.Random.init(0x31415926);
    var world: a.env.Environment = .{};
    var episode: u32 = 0;
    _ = world.reset(0xa0000000);
    // Reservoir sampling of all 50 complete greedy calibration episodes.
    var seen: usize = 0;
    while (episode < 50) {
        const state = try world.state.normalized();
        const slot = if (seen < 2048) seen else rng.index(seen + 1);
        if (slot < 2048) result[slot] = .{ .input = state, .target = .{ 0, 0 } };
        seen += 1;
        const q = model.predict(&state);
        _ = try world.step(if (try z.rl.dqn.greedy(&q) == 0) .left else .right);
        if (world.done) {
            episode += 1;
            _ = world.reset(0xa0000000 + episode);
        }
    }
    const populated = @min(seen, 2048);
    for (populated..2048) |i| result[i] = result[i % populated];
    if (kind == .representative) for (result[0..2048]) |*sample| {
        sample.* = .{ .input = .{ (rng.unit() * 2 - 1) * 0.8, (rng.unit() * 2 - 1) * 0.4, rng.unit() * 2 - 1, (rng.unit() * 2 - 1) * 0.4 }, .target = .{ 0, 0 } };
    };
    if (kind == .hybrid) for (0..1024) |i| {
        result[i * 2] = baseline[i * baseline.len / 1024];
    };
    // Baseline/hybrid/representative retain the same full input-domain anchor.
    result[2048] = if (kind == .rollout) result[0] else .{ .input = .{ 1, 0, 0, 0 }, .target = .{ 0, 0 } };
    return result;
}
pub fn quantize(comptime S: type, model: *const z.Trainer(S), calibration: []const a.T.Sample, output_factor: f32) !z.export_model.Quantized(S) {
    if (!std.math.isFinite(output_factor) or output_factor <= 0) return error.InvalidOutputFactor;
    var q = if (S.output_len == 2) try z.export_model.Quantized(S).calibrate(model, calibration) else blk: {
        if (calibration.len > 2049) return error.TooManyCalibrationSamples;
        var converted: [2049]z.Trainer(S).Sample = undefined;
        for (calibration, converted[0..calibration.len]) |sample, *dest| dest.* = .{ .input = sample.input, .target = .{0} };
        break :blk try z.export_model.Quantized(S).calibrate(model, converted[0..calibration.len]);
    };
    const l = S.layer_count - 1;
    q.scales[S.layer_count] *= output_factor;
    var params = try z.export_model.coefficient(@as(f64, q.params[l].input_scale.?) * q.params[l].weight_scale.? / q.scales[S.layer_count]);
    params.input_scale = q.params[l].input_scale;
    params.weight_scale = q.params[l].weight_scale;
    params.output_scale = q.scales[S.layer_count];
    q.params[l] = params;
    return q;
}

pub fn action(output: anytype) usize {
    return if (output.len == 1) @intFromBool(output[0] > 0) else @intFromBool(output[1] > output[0]);
}

/// Positive hidden-unit rescaling: ReLU(g*x)=g*ReLU(x).
/// Multiply incoming weights/bias by g, divide outgoing weights by g.
/// Same real-arithmetic policy; no extra inference operations or stored scales.
pub fn equalize(model: *const a.T, calibration: []const a.T.Sample) a.T {
    var result = model.*;
    inline for (0..2) |l| {
        var maxima: [16]f32 = @splat(0);
        for (calibration) |sample| {
            var activations: a.T.Activations = undefined;
            result.forward(&sample.input, &activations);
            for (&maxima, activations[l + 1][0..16]) |*maximum, v| maximum.* = @max(maximum.*, v);
        }
        for (maxima, 0..) |maximum, o| {
            if (maximum <= 0.000001) continue;
            const gain = std.math.clamp(1 / maximum, 0.125, 8);
            const base = a.S.offsets[l];
            for (0..a.S.fanins[l]) |i| result.parameters[base + o * a.S.fanins[l] + i] *= gain;
            result.parameters[base + a.S.weight_counts[l] + o] *= gain;
            const next = a.S.offsets[l + 1];
            for (0..a.S.widths[l + 2]) |i| result.parameters[next + i * 16 + o] /= gain;
        }
    }
    return result;
}

/// Calibration-only mean preactivation error correction; weights and runtime stay integer.
pub fn correctBiases(comptime S: type, model: *const z.Trainer(S), q: *z.export_model.Quantized(S), calibration: []const a.T.Sample) !void {
    if (calibration.len == 0) return error.EmptyCalibration;
    inline for (0..3) |l| {
        var errors: [16]f64 = @splat(0);
        for (calibration) |sample| {
            var f: z.Trainer(S).Activations = undefined;
            model.forward(&sample.input, &f);
            var values: [2][16]i8 = undefined;
            for (sample.input, 0..) |v, i| values[0][i] = try z.export_model.quantizeInput(v, q.scales[0]);
            inline for (0..l + 1) |k| {
                const base = S.offsets[k];
                for (0..S.widths[k + 1]) |o| {
                    var acc: i64 = q.biases[base + o];
                    for (0..S.fanins[k]) |i| acc += @as(i64, values[k % 2][i]) * q.weights[base + o * S.fanins[k] + i];
                    if (k == l) {
                        var real: f64 = model.parameters[base + S.weight_counts[k] + o];
                        for (0..S.fanins[k]) |i| real += @as(f64, f[k][i]) * model.parameters[base + o * S.fanins[k] + i];
                        errors[o] += real - @as(f64, @floatFromInt(acc)) * q.scales[k] * q.params[k].weight_scale.?;
                    } else {
                        if (acc < std.math.minInt(i32) or acc > std.math.maxInt(i32)) return error.AccumulatorOverflow;
                        var v = z.quant.requantize(@intCast(acc), q.params[k]);
                        if (S.layers[k].activation == .relu) v = @max(0, v);
                        values[(k + 1) % 2][o] = v;
                    }
                }
            }
        }
        for (0..S.widths[l + 1]) |o| {
            const delta = @round(errors[o] / @as(f64, @floatFromInt(calibration.len)) / (@as(f64, q.scales[l]) * q.params[l].weight_scale.?));
            const bias = @as(f64, @floatFromInt(q.biases[S.offsets[l] + o])) + delta;
            if (!std.math.isFinite(bias) or @abs(bias) > 2147483647) return error.BiasOverflow;
            q.biases[S.offsets[l] + o] = @intFromFloat(bias);
            var bound: u64 = @abs(@as(i64, q.biases[S.offsets[l] + o]));
            for (q.weights[S.offsets[l] + o * S.fanins[l] ..][0..S.fanins[l]]) |w| bound += 128 * @as(u64, @abs(@as(i16, w)));
            if (bound > 2147483647) return error.AccumulatorOverflow;
        }
    }
}

pub const Selected = struct { model: z.Trainer(Difference), quantized: z.export_model.Quantized(Difference), calibration: []a.T.Sample };
/// Frozen on development seeds, before opening the new final-test partition.
pub fn selected(allocator: std.mem.Allocator, model: *const a.T, baseline: []const a.T.Sample) !Selected {
    const calibration = try samples(allocator, .rollout, model, baseline);
    const balanced = equalize(model, calibration);
    const transformed = difference(&balanced);
    var quantized = try quantize(Difference, &transformed, calibration, 0.125);
    try correctBiases(Difference, &transformed, &quantized, calibration);
    return .{ .model = transformed, .quantized = quantized, .calibration = calibration };
}
pub fn writeVerification(selected_model: *const Selected, writer: *std.Io.Writer) !void {
    var converted: [128]z.Trainer(Difference).Sample = undefined;
    for (selected_model.calibration[0..128], &converted) |sample, *dest| dest.* = .{ .input = sample.input, .target = .{0} };
    try selected_model.quantized.writeVerification(writer, &converted);
}
