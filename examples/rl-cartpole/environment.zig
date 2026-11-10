//! Independent CartPole equations; standard constants, f32 explicit Euler.
const std = @import("std");
const Random = @import("zinn").rl.Random;
pub const Action = enum { left, right };
pub const State = struct {
    x: f32 = 0,
    x_dot: f32 = 0,
    theta: f32 = 0,
    theta_dot: f32 = 0,
    pub fn finite(self: State) bool {
        return std.math.isFinite(self.x) and std.math.isFinite(self.x_dot) and std.math.isFinite(self.theta) and std.math.isFinite(self.theta_dot);
    }
    pub fn normalized(self: State) ![4]f32 {
        if (!self.finite()) return error.NonFiniteState;
        return .{ std.math.clamp(self.x / 2.4, -1, 1), std.math.clamp(self.x_dot / 3, -1, 1), std.math.clamp(self.theta / angle_limit, -1, 1), std.math.clamp(self.theta_dot / 3.5, -1, 1) };
    }
};
pub const angle_limit: f32 = 12.0 * std.math.pi / 180.0;
pub const Result = struct { state: State, reward: f32 = 1, terminated: bool, truncated: bool };
pub const Environment = struct {
    state: State = .{},
    steps: usize = 0,
    done: bool = false,
    pub fn reset(self: *Environment, seed: u32) State {
        var rng = Random.init(seed);
        self.* = .{ .state = .{ .x = rng.unit() * 0.1 - 0.05, .x_dot = rng.unit() * 0.1 - 0.05, .theta = rng.unit() * 0.1 - 0.05, .theta_dot = rng.unit() * 0.1 - 0.05 } };
        return self.state;
    }
    pub fn step(self: *Environment, action: Action) !Result {
        if (self.done) return error.EpisodeFinished;
        if (!self.state.finite()) return error.NonFiniteState;
        const s = self.state;
        const sine = @sin(s.theta);
        const cosine = @cos(s.theta);
        const force: f32 = if (action == .right) 10 else -10;
        const temp = (force + 0.05 * s.theta_dot * s.theta_dot * sine) / 1.1;
        const angular = (9.8 * sine - cosine * temp) / (0.5 * (4.0 / 3.0 - 0.1 * cosine * cosine / 1.1));
        const linear = temp - 0.05 * angular * cosine / 1.1;
        const next: State = .{ .x = s.x + 0.02 * s.x_dot, .x_dot = s.x_dot + 0.02 * linear, .theta = s.theta + 0.02 * s.theta_dot, .theta_dot = s.theta_dot + 0.02 * angular };
        if (!next.finite()) return error.NonFiniteState;
        self.state = next;
        self.steps += 1;
        const terminated = @abs(next.x) > 2.4 or @abs(next.theta) > angle_limit;
        const truncated = self.steps >= 500;
        self.done = terminated or truncated;
        return .{ .state = next, .terminated = terminated, .truncated = truncated };
    }
};
