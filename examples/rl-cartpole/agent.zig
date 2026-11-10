const std = @import("std");
const z = @import("zinn");
pub const env = @import("environment.zig");
pub const S = @import("model.zig").Structure;
pub const Agent = z.rl.Dqn(S);
pub const T = Agent.T;
pub const Options = struct { episodes: usize = 1000, seed: u32 = 42, replay_capacity: usize = 10000, dqn: z.rl.dqn.Options = .{} };
pub const Metrics = struct { successes: usize = 0, failures: usize = 0, episodes: usize = 0, reward: usize = 0, mean100: f32 = 0, maximum: usize = 0, evaluation: f32 = 0, best_evaluation: f32 = 0, best_episode: usize = 0 };
pub fn episodeSeed(seed: u32, episode: usize) u32 {
    return (seed *% 0x9e3779b9 +% @as(u32, @truncate(episode)) *% 0x85ebca6b) & 0x7fffffff;
}
pub const Evaluation = @import("evaluation.zig").Evaluation;
pub const evaluate = @import("evaluation.zig").evaluate;
pub const evaluateSeeds = @import("evaluation.zig").evaluateSeeds;
pub const Session = struct {
    agent: Agent,
    best: T,
    world: env.Environment = .{},
    options: Options,
    metrics: Metrics = .{},
    history: [100]usize = @splat(0),
    last_action: usize = 0,
    pub fn init(options: Options, storage: []z.rl.Transition(4)) !Session {
        if (options.episodes == 0 or storage.len != options.replay_capacity) return error.InvalidSessionOptions;
        var self: Session = .{ .agent = try Agent.init(options.seed, storage, options.dqn), .best = T.init(options.seed), .options = options };
        _ = self.world.reset(episodeSeed(options.seed, 0));
        return self;
    }
    pub fn step(self: *Session) !?Metrics {
        if (self.metrics.episodes >= self.options.episodes) return null;
        const state = try self.world.state.normalized();
        self.last_action = try self.agent.selectAction(&state);
        const transition = try self.world.step(if (self.last_action == 0) .left else .right);
        try self.agent.observe(.{ .state = state, .action = self.last_action, .reward = transition.reward, .next_state = try transition.state.normalized(), .terminated = transition.terminated, .truncated = transition.truncated });
        if (!self.world.done) return null;
        const episode = self.metrics.episodes;
        self.history[episode % 100] = self.world.steps;
        self.metrics.episodes += 1;
        self.metrics.reward = self.world.steps;
        if (transition.terminated) self.metrics.failures += 1 else self.metrics.successes += 1;
        self.metrics.maximum = @max(self.metrics.maximum, self.world.steps);
        var sum: usize = 0;
        for (self.history[0..@min(100, self.metrics.episodes)]) |r| sum += r;
        self.metrics.mean100 = @as(f32, @floatFromInt(sum)) / @as(f32, @floatFromInt(@min(100, self.metrics.episodes)));
        if (self.metrics.episodes % 50 == 0 or self.metrics.episodes == self.options.episodes) {
            self.metrics.evaluation = (try evaluateSeeds(&self.agent.online, false, 0x80000000)).mean;
            if (self.metrics.evaluation > self.metrics.best_evaluation) {
                self.metrics.best_evaluation = self.metrics.evaluation;
                self.metrics.best_episode = self.metrics.episodes;
                self.best = self.agent.online;
            }
        }
        _ = self.world.reset(episodeSeed(self.options.seed, self.metrics.episodes));
        return self.metrics;
    }
};
