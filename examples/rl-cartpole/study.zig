//! Host experiment runner. Final seeds are inaccessible in development mode.
const std = @import("std");
const z = @import("zinn");
const a = @import("agent.zig");
const p = @import("policy_export.zig");
const Evaluation = @import("evaluation.zig");
pub const Stats = struct {
    mean: f64,
    median: f64,
    standard_deviation: f64,
    minimum: usize,
    maximum: usize,
    successes: usize,
    pub fn fromEvaluation(value: Evaluation.Evaluation) Stats {
        var result = from(value.rewards);
        result.successes = value.successes;
        return result;
    }
    pub fn from(rewards: [50]usize) Stats {
        var sorted = rewards;
        std.mem.sort(usize, &sorted, {}, std.sort.asc(usize));
        var sum: f64 = 0;
        for (rewards) |r| sum += @floatFromInt(r);
        const mean = sum / 50;
        var variance: f64 = 0;
        for (rewards) |r| {
            const delta = @as(f64, @floatFromInt(r)) - mean;
            variance += delta * delta / 50;
        }
        var successes: usize = 0;
        for (rewards) |r| if (r == 500) {
            successes += 1;
        };
        return .{ .mean = mean, .median = @as(f64, @floatFromInt(sorted[24] + sorted[25])) / 2, .standard_deviation = @sqrt(variance), .minimum = sorted[0], .maximum = sorted[49], .successes = successes };
    }
};
pub fn rollout(comptime S: type, model: *const z.export_model.Quantized(S), base: u32) !Evaluation.Evaluation {
    var result: Evaluation.Evaluation = .{};
    for (&result.rewards, 0..) |*reward, i| {
        var world: a.env.Environment = .{};
        _ = world.reset(base + @as(u32, @intCast(i)));
        while (!world.done) {
            const state = try world.state.normalized();
            var input: [4]i8 = undefined;
            for (&input, state) |*v, f| v.* = try z.export_model.quantizeInput(f, model.scales[0]);
            const out = model.infer(&input);
            _ = try world.step(if (p.action(out) == 0) .left else .right);
        }
        reward.* = world.steps;
        result.maximum = @max(result.maximum, world.steps);
        result.mean += @as(f32, @floatFromInt(world.steps)) / 50;
        if (world.steps == 500 and @abs(world.state.x) <= 2.4 and @abs(world.state.theta) <= a.env.angle_limit) result.successes += 1;
    }
    return result;
}
pub const Counts = struct { total: usize = 0, mismatches: usize = 0 };
pub const Analysis = struct {
    transformed_float_mismatches: usize = 0,
    input_absolute_error: f64 = 0,
    count: usize = 0,
    mismatches: usize = 0,
    input_clips: usize = 0,
    output_ties: usize = 0,
    centered_mismatches: usize = 0,
    difference_mismatches: usize = 0,
    margins: [6]Counts = @splat(.{}),
    angles: [4]Counts = @splat(.{}),
    angular_velocities: [4]Counts = @splat(.{}),
    input_min: [4]f32 = @splat(std.math.inf(f32)),
    input_max: [4]f32 = @splat(-std.math.inf(f32)),
    layer_absolute_error: [3]f64 = @splat(0),
    layer_count: [3]usize = @splat(0),
    layer_clips: [3]usize = @splat(0),
    float_min: [3]f32 = @splat(std.math.inf(f32)),
    float_max: [3]f32 = @splat(-std.math.inf(f32)),
    margin_absolute_error: f64 = 0,
};
pub fn diagnose(comptime S: type, original: *const a.T, transformed: *const z.Trainer(S), q: *const z.export_model.Quantized(S), base: u32, integer_trajectory: bool, writer: ?*std.Io.Writer) !Analysis {
    var result: Analysis = .{};
    const centered = z.rl.centeredActionHead(a.S, original);
    const diff = p.difference(original);
    if (writer) |w| try w.writeAll("episode,step,x,velocity,angle,angular_velocity,q_left,q_right,center_left,center_right,int_left_or_difference,int_right,float_action,int_action,matched,float_margin,int_margin,q_x,q_velocity,q_angle,q_angular_velocity,input_clips,l0_mae,l1_mae,l2_mae,l0_clips,l1_clips,l2_clips,l0_float_min,l0_float_max,l0_int_min,l0_int_max,l1_float_min,l1_float_max,l1_int_min,l1_int_max,l2_float_min,l2_float_max,l2_int_min,l2_int_max\n");
    for (0..50) |episode| {
        var world: a.env.Environment = .{};
        _ = world.reset(base + @as(u32, @intCast(episode)));
        while (!world.done) {
            const state = try world.state.normalized();
            const raw = original.predict(&state);
            const c = centered.predict(&state);
            const d = diff.predict(&state);
            const fa = try z.rl.dqn.greedy(&raw);
            var input: [4]i8 = undefined;
            var clips: usize = 0;
            for (&input, state, 0..) |*v, f, i| {
                const scaled = @round(f / q.scales[0]);
                clips += @intFromBool(scaled < -128 or scaled > 127);
                v.* = try z.export_model.quantizeInput(f, q.scales[0]);
                result.input_absolute_error += @abs(@as(f64, f) - @as(f64, @floatFromInt(v.*)) * q.scales[0]);
                result.input_min[i] = @min(result.input_min[i], f);
                result.input_max[i] = @max(result.input_max[i], f);
            }
            const output = q.infer(&input);
            const ia = p.action(output);
            const mismatch = fa != ia;
            const tf = transformed.predict(&state);
            result.transformed_float_mismatches += @intFromBool(fa != p.action(tf));
            const margin = raw[1] - raw[0];
            const imargin = (if (S.output_len == 1) @as(i16, output[0]) else @as(i16, output[1]) - output[0]);
            result.count += 1;
            result.mismatches += @intFromBool(mismatch);
            result.input_clips += clips;
            result.output_ties += @intFromBool(imargin == 0);
            result.centered_mismatches += @intFromBool(fa != try z.rl.dqn.greedy(&c));
            result.difference_mismatches += @intFromBool(fa != @as(usize, @intFromBool(d[0] > 0)));
            result.margin_absolute_error += @abs(@as(f64, margin) - @as(f64, @floatFromInt(imargin)) * q.scales[3]);
            const bin: usize = if (@abs(margin) < 0.001) 0 else if (@abs(margin) < 0.01) 1 else if (@abs(margin) < 0.05) 2 else if (@abs(margin) < 0.2) 3 else if (@abs(margin) < 1) 4 else 5;
            result.margins[bin].total += 1;
            result.margins[bin].mismatches += @intFromBool(mismatch);
            inline for (.{ .{ &result.angles, @abs(state[2]) }, .{ &result.angular_velocities, @abs(state[3]) } }) |item| {
                const j: usize = if (item[1] < 0.1) 0 else if (item[1] < 0.3) 1 else if (item[1] < 0.7) 2 else 3;
                item[0][j].total += 1;
                item[0][j].mismatches += @intFromBool(mismatch);
            }
            var acts: z.Trainer(S).Activations = undefined;
            transformed.forward(&state, &acts);
            var buffers: [2][16]i8 = undefined;
            @memcpy(buffers[0][0..4], &input);
            var errors: [3]f64 = @splat(0);
            var ranges: [3][4]f32 = @splat(.{ std.math.inf(f32), -std.math.inf(f32), std.math.inf(f32), -std.math.inf(f32) });
            var layer_clips: [3]usize = @splat(0);
            inline for (S.layers, 0..) |layer, l| {
                const offset = S.offsets[l];
                for (0..S.widths[l + 1]) |o| {
                    var acc: i64 = q.biases[offset + o];
                    for (0..S.fanins[l]) |i| acc += @as(i64, buffers[l % 2][i]) * q.weights[offset + o * S.fanins[l] + i];
                    const prod = acc * q.params[l].multiplier;
                    const denominator = @as(u64, 1) << q.params[l].shift;
                    const magnitude = (@abs(prod) + denominator / 2) / denominator;
                    const signed = if (prod < 0) -@as(i64, @intCast(magnitude)) else @as(i64, @intCast(magnitude));
                    layer_clips[l] += @intFromBool(signed > 127 or (signed < -128 and layer.activation != .relu));
                    var value: i8 = @intCast(std.math.clamp(signed, -128, 127));
                    if (layer.activation == .relu) value = @max(value, 0);
                    buffers[(l + 1) % 2][o] = value;
                    ranges[l][0] = @min(ranges[l][0], acts[l + 1][o]);
                    ranges[l][1] = @max(ranges[l][1], acts[l + 1][o]);
                    const decoded = @as(f32, @floatFromInt(value)) * q.scales[l + 1];
                    ranges[l][2] = @min(ranges[l][2], decoded);
                    ranges[l][3] = @max(ranges[l][3], decoded);
                    errors[l] += @abs(@as(f64, acts[l + 1][o]) - @as(f64, @floatFromInt(value)) * q.scales[l + 1]);
                    result.float_min[l] = @min(result.float_min[l], acts[l + 1][o]);
                    result.float_max[l] = @max(result.float_max[l], acts[l + 1][o]);
                }
                result.layer_absolute_error[l] += errors[l];
                result.layer_count[l] += S.widths[l + 1];
                result.layer_clips[l] += layer_clips[l];
                errors[l] /= @floatFromInt(S.widths[l + 1]);
            }
            if (!std.mem.eql(i8, buffers[1][0..S.output_len], &output)) return error.TraceMismatch;
            if (writer) |w| {
                try w.print("{d},{d},{d},{d},{d},{d},{d},{d},{d},{d},{d},{d},{d},{d},{},{d},{d},{d},{d},{d},{d},{d},{d},{d},{d},{d},{d},{d}", .{ episode, world.steps, state[0], state[1], state[2], state[3], raw[0], raw[1], c[0], c[1], output[0], if (S.output_len == 1) @as(i8, 0) else output[1], fa, ia, !mismatch, margin, imargin, input[0], input[1], input[2], input[3], clips, errors[0], errors[1], errors[2], layer_clips[0], layer_clips[1], layer_clips[2] });
                for (ranges) |range| try w.print(",{d},{d},{d},{d}", .{ range[0], range[1], range[2], range[3] });
                try w.writeByte('\n');
            }
            _ = try world.step(if ((if (integer_trajectory) ia else fa) == 0) .left else .right);
        }
    }
    return result;
}
fn save(init: std.process.Init, dir: []const u8, name: []const u8, data: []const u8) !void {
    const path = try std.fs.path.join(init.arena.allocator(), &.{ dir, name });
    try std.Io.Dir.cwd().writeFile(init.io, .{ .sub_path = path, .data = data });
}
pub fn main(init: std.process.Init) !void {
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    if (args.len != 5) return error.ExpectedCheckpointCalibrationOutputPhase;
    const allocator = init.arena.allocator();
    var model = a.T.init(0);
    try model.decode(try std.Io.Dir.cwd().readFileAlloc(init.io, args[1], allocator, .limited(1024 * 1024)));
    const baseline = try z.data.csv(a.T, allocator, try std.Io.Dir.cwd().readFileAlloc(init.io, args[2], allocator, .limited(16 * 1024 * 1024)), false);
    const final = std.mem.eql(u8, args[4], "final");
    if (!final and !std.mem.eql(u8, args[4], "development")) return error.InvalidPhase;
    const base: u32 = if (final) 0xe1000000 else 0x90000000;
    const float = try a.evaluateSeeds(&model, false, base);
    const random = try a.evaluateSeeds(&model, true, base);
    if (final) {
        const centered = z.rl.centeredActionHead(a.S, &model);
        const baseline_q = try Evaluation.Q.calibrate(&centered, baseline);
        const improved = try p.selected(allocator, &model, baseline);
        var analyses: [4]Analysis = undefined;
        inline for (.{ false, true }) |integer_trajectory| {
            inline for (.{ false, true }) |new| {
                const S = if (new) p.Difference else a.S;
                const transformed = if (new) improved.model else centered;
                const quantized = if (new) improved.quantized else baseline_q;
                var diagnostic: std.Io.Writer.Allocating = .init(allocator);
                const index: usize = @as(usize, @intFromBool(new)) * 2 + @intFromBool(integer_trajectory);
                analyses[index] = try diagnose(S, &model, &transformed, &quantized, base, integer_trajectory, &diagnostic.writer);
                try save(init, args[3], (if (new) "improved" else "baseline") ++ (if (integer_trajectory) "-integer.csv" else "-float.csv"), diagnostic.written());
            }
        }
        const old_rewards = try rollout(a.S, &baseline_q, base);
        const new_rewards = try rollout(p.Difference, &improved.quantized, base);
        const summary = try std.json.Stringify.valueAlloc(allocator, .{ .seed = model.seed, .phase = args[4], .base_seed = base, .random = Stats.fromEvaluation(random), .float = Stats.fromEvaluation(float), .baseline = Stats.fromEvaluation(old_rewards), .improved = Stats.fromEvaluation(new_rewards), .float_rewards = float.rewards, .baseline_rewards = old_rewards.rewards, .improved_rewards = new_rewards.rewards, .analyses = analyses }, .{});
        try save(init, args[3], "final.json", summary);
        return;
    }
    var csv: std.Io.Writer.Allocating = .init(allocator);
    try csv.writer.writeAll("calibration,equalized,strategy,output_factor,bias_correction,mean,median,std,min,max,successes,mismatches,samples,input_clips,ties\n");
    var json: std.Io.Writer.Allocating = .init(allocator);
    try json.writer.writeAll("[\n");
    var first = true;
    inline for (.{ p.Calibration.baseline, .representative, .rollout, .hybrid }) |kind| {
        const calibration = try p.samples(allocator, kind, &model, baseline);
        inline for (.{ false, true }) |equalized| {
            const source_model = if (equalized) p.equalize(&model, calibration) else model;
            inline for (.{ p.Strategy.centered, .difference }) |strategy| {
                const S = if (strategy == .centered) a.S else p.Difference;
                const transformed = if (strategy == .centered) z.rl.centeredActionHead(a.S, &source_model) else p.difference(&source_model);
                inline for (.{ @as(f32, 1), @as(f32, 0.125) }) |factor| {
                    if (final) return error.FinalStrategyNotFrozen;
                    inline for (.{ false, true }) |bias_correction| {
                        var quantized = try p.quantize(S, &transformed, calibration, factor);
                        if (bias_correction) try p.correctBiases(S, &transformed, &quantized, calibration);
                        const rewards = try rollout(S, &quantized, base);
                        const stats = Stats.fromEvaluation(rewards);
                        const analysis = try diagnose(S, &model, &transformed, &quantized, base, false, null);
                        try csv.writer.print("{s},{},{s},{d},{},{d},{d},{d},{d},{d},{d},{d},{d},{d},{d}\n", .{ @tagName(kind), equalized, @tagName(strategy), factor, bias_correction, stats.mean, stats.median, stats.standard_deviation, stats.minimum, stats.maximum, stats.successes, analysis.mismatches, analysis.count, analysis.input_clips, analysis.output_ties });
                        if (!first) try json.writer.writeAll(",\n");
                        first = false;
                        try std.json.Stringify.value(.{ .calibration = kind, .equalized = equalized, .strategy = strategy, .output_factor = factor, .bias_correction = bias_correction, .stats = stats, .rewards = rewards.rewards, .analysis = analysis, .scales = quantized.scales }, .{}, &json.writer);
                    }
                }
            }
        }
    }
    try json.writer.writeAll("\n]\n");
    try save(init, args[3], "candidates.json", json.written());
    try save(init, args[3], "candidates.csv", csv.written());
    const summary = try std.json.Stringify.valueAlloc(allocator, .{ .seed = model.seed, .phase = args[4], .base_seed = base, .float = Stats.fromEvaluation(float), .random = Stats.fromEvaluation(random) }, .{});
    try save(init, args[3], "summary.json", summary);
}
