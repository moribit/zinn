const std = @import("std");
const train = @import("../train.zig");
const replay = @import("replay.zig");
const Random = @import("random.zig").Random;
pub const Options = struct {
    rate: f32 = 0.005,
    gamma: f32 = 0.95,
    epsilon_start: f32 = 1,
    epsilon_end: f32 = 0.05,
    epsilon_steps: usize = 10000,
    batch: usize = 32,
    warmup: usize = 512,
    train_every: usize = 1,
    target_interval: usize = 100,
    reward_scale: f32 = 1,
    td_clip: f32 = 1,
    max_q: f32 = 100,
    pub fn validate(self: Options) !void {
        inline for (.{ "rate", "gamma", "epsilon_start", "epsilon_end", "reward_scale", "td_clip", "max_q" }) |field|
            if (!std.math.isFinite(@field(self, field))) return error.InvalidDqnOptions;
        if (self.rate <= 0 or self.gamma < 0 or self.gamma > 1 or self.epsilon_end < 0 or self.epsilon_start > 1 or self.epsilon_end > self.epsilon_start or self.batch == 0 or self.batch > 128 or self.warmup < self.batch or self.epsilon_steps == 0 or self.train_every == 0 or self.target_interval == 0 or self.reward_scale <= 0 or self.td_clip <= 0 or self.max_q <= 0) return error.InvalidDqnOptions;
    }
};
pub fn greedy(values: []const f32) !usize {
    if (values.len == 0) return error.EmptyActions;
    var best: usize = 0;
    for (values, 0..) |v, i| {
        if (!std.math.isFinite(v)) return error.NonFiniteQ;
        if (v > values[best]) best = i;
    }
    return best;
}
/// Truncation is deliberately not terminal: bootstrap from the final observation.
pub fn bellman(reward: f32, terminated: bool, next: []const f32, gamma: f32) !f32 {
    if (!std.math.isFinite(reward) or !std.math.isFinite(gamma) or gamma < 0 or gamma > 1) return error.InvalidBellmanInput;
    if (terminated) return reward;
    const result = reward + gamma * next[try greedy(next)];
    if (!std.math.isFinite(result)) return error.NonFiniteQ;
    return result;
}
pub fn epsilon(options: Options, steps: usize) f32 {
    const fraction = @as(f32, @floatFromInt(@min(steps, options.epsilon_steps))) / @as(f32, @floatFromInt(options.epsilon_steps));
    return options.epsilon_start + (options.epsilon_end - options.epsilon_start) * fraction;
}
pub fn Dqn(comptime S: type) type {
    if (S.layers[S.layer_count - 1].activation != .none) @compileError("DQN requires a linear Q output");
    return struct {
        const Self = @This();
        pub const T = train.Trainer(S);
        online: T,
        target: T,
        replay: replay.Replay(S.input_len),
        rng: Random,
        options: Options,
        steps: usize = 0,
        updates: usize = 0,
        last_loss: f32 = 0,
        pub fn init(seed: u32, storage: []replay.Transition(S.input_len), options: Options) !Self {
            try options.validate();
            if (storage.len < options.warmup) return error.ReplayTooSmall;
            const model = T.init(seed);
            return .{ .online = model, .target = model, .replay = try replay.Replay(S.input_len).init(storage), .rng = Random.init(seed ^ 0x9e3779b9), .options = options };
        }
        fn values(model: *const T, state: *const [S.input_len]f32, max_q: f32) ![S.output_len]f32 {
            for (state) |v| if (!std.math.isFinite(v)) return error.NonFiniteState;
            const q = model.predict(state);
            for (q) |v| if (!std.math.isFinite(v) or @abs(v) > max_q) return error.DivergedQ;
            return q;
        }
        pub fn qValues(self: *const Self, state: *const [S.input_len]f32) ![S.output_len]f32 {
            return values(&self.online, state, self.options.max_q);
        }
        pub fn selectAction(self: *Self, state: *const [S.input_len]f32) !usize {
            const q = try self.qValues(state);
            if (self.rng.unit() < epsilon(self.options, self.steps)) return self.rng.index(S.output_len);
            return greedy(&q);
        }
        pub fn syncTarget(self: *Self) void {
            self.target = self.online;
        }
        pub fn observe(self: *Self, item: replay.Transition(S.input_len)) !void {
            if (item.action >= S.output_len or !std.math.isFinite(item.reward)) return error.InvalidTransition;
            for (item.state) |v| if (!std.math.isFinite(v)) return error.NonFiniteState;
            for (item.next_state) |v| if (!std.math.isFinite(v)) return error.NonFiniteState;
            self.replay.append(item);
            self.steps += 1;
            if (self.replay.count < self.options.warmup or self.steps % self.options.train_every != 0) return;
            var batch: [128]T.Sample = undefined;
            for (batch[0..self.options.batch]) |*sample| {
                const experience = try self.replay.sample(&self.rng);
                const current = try self.qValues(&experience.state);
                const next = if (experience.terminated) @as([S.output_len]f32, @splat(0)) else try values(&self.target, &experience.next_state, self.options.max_q);
                const goal = try bellman(experience.reward * self.options.reward_scale, experience.terminated, &next, self.options.gamma);
                sample.* = .{ .input = experience.state, .target = current };
                // Frozen online predictions make unselected action deltas exactly zero
                // during this batch. Clipped TD residual bounds the MSE gradient.
                sample.target[experience.action] = current[experience.action] + std.math.clamp(goal - current[experience.action], -self.options.td_clip, self.options.td_clip);
            }
            self.last_loss = try self.online.trainBatch(batch[0..self.options.batch], self.options.rate, .mse);
            if (!std.math.isFinite(self.last_loss)) return error.DivergedQ;
            for (self.online.parameters) |v| if (!std.math.isFinite(v)) return error.DivergedQ;
            self.updates += 1;
            if (self.updates % self.options.target_interval == 0) self.syncTarget();
        }
    };
}
