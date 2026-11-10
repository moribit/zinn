const std = @import("std");
const z = @import("zinn");
const env = @import("environment.zig");
const S = @import("model.zig").Structure;
const T = z.Trainer(S);
pub const Q = z.export_model.Quantized(S);
pub const Evaluation = struct { rewards: [50]usize = @splat(0), mean: f32 = 0, maximum: usize = 0, successes: usize = 0 };
pub fn evaluate(model: *const T, random: bool) !Evaluation {
    return evaluateSeeds(model, random, 0xc0000000);
}
pub fn evaluateSeeds(model: *const T, random: bool, base_seed: u32) !Evaluation {
    var result: Evaluation = .{};
    for (&result.rewards, 0..) |*reward, i| {
        var world: env.Environment = .{};
        _ = world.reset(base_seed + @as(u32, @intCast(i)));
        var rng = z.rl.Random.init(0xfedcba98 + @as(u32, @intCast(i)));
        while (!world.done) {
            const input = try world.state.normalized();
            const q = model.predict(&input);
            const action = if (random) rng.index(2) else try z.rl.dqn.greedy(&q);
            const step = try world.step(if (action == 0) .left else .right);
            if (step.truncated and !step.terminated) result.successes += 1;
        }
        reward.* = world.steps;
        result.mean += @as(f32, @floatFromInt(world.steps)) / 50;
        result.maximum = @max(result.maximum, world.steps);
    }
    return result;
}

pub fn evaluateInteger(model: *const Q, base_seed: u32) !Evaluation {
    var result: Evaluation = .{};
    for (&result.rewards, 0..) |*reward, i| {
        var world: env.Environment = .{};
        _ = world.reset(base_seed + @as(u32, @intCast(i)));
        while (!world.done) {
            const state = try world.state.normalized();
            var input: [4]i8 = undefined;
            for (&input, state) |*v, f| v.* = try z.export_model.quantizeInput(f, model.scales[0]);
            const output = model.infer(&input);
            const step = try world.step(if (output[1] > output[0]) .right else .left);
            if (step.truncated and !step.terminated) result.successes += 1;
        }
        reward.* = world.steps;
        result.mean += @as(f32, @floatFromInt(world.steps)) / 50;
        result.maximum = @max(result.maximum, world.steps);
    }
    return result;
}
pub const Agreement = struct { matched: usize = 0, mismatched: usize = 0, rate: f32 = 0 };
pub fn agreement(model: *const T, quantized: *const Q) !Agreement {
    var result: Agreement = .{};
    for (0..50) |i| {
        var world: env.Environment = .{};
        _ = world.reset(0xc0000000 + @as(u32, @intCast(i)));
        while (!world.done) {
            const state = try world.state.normalized();
            const q = model.predict(&state);
            const action = try z.rl.dqn.greedy(&q);
            var input: [4]i8 = undefined;
            for (&input, state) |*v, f| v.* = try z.export_model.quantizeInput(f, quantized.scales[0]);
            const output = quantized.infer(&input);
            const integer: @TypeOf(action) = if (output[1] > output[0]) 1 else 0;
            if (action == integer) result.matched += 1 else result.mismatched += 1;
            _ = try world.step(if (action == 0) .left else .right);
        }
    }
    result.rate = 100 * @as(f32, @floatFromInt(result.matched)) / @as(f32, @floatFromInt(result.matched + result.mismatched));
    return result;
}
