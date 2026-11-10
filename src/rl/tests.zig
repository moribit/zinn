const std = @import("std");
const dqn = @import("dqn.zig");
const Random = @import("random.zig").Random;
const replay = @import("replay.zig");
const S = @import("../definition.zig").Definition(2, &.{.{ .units = 2 }});
const Agent = dqn.Dqn(S);
test "terminal target, time-limit bootstrap and finite validation" {
    try std.testing.expectEqual(@as(f32, 1), try dqn.bellman(1, true, &.{ 10, 20 }, 0.5));
    try std.testing.expectEqual(@as(f32, 11), try dqn.bellman(1, false, &.{ 10, 20 }, 0.5));
    try std.testing.expectEqual(@as(usize, 0), try dqn.greedy(&.{ 2, 2 }));
    try std.testing.expectError(error.NonFiniteQ, dqn.greedy(&.{ 0, std.math.nan(f32) }));
    try std.testing.expectError(error.InvalidBellmanInput, dqn.bellman(1, false, &.{1}, 2));
    try std.testing.expectError(error.InvalidBellmanInput, dqn.bellman(std.math.inf(f32), true, &.{}, 0.9));
}
test "ring overwrite and reproducible sampling with caller-owned storage" {
    var storage: [3]replay.Transition(2) = undefined;
    var buffer = try replay.Replay(2).init(&storage);
    var r1 = Random.init(42);
    var r2 = Random.init(42);
    try std.testing.expectError(error.EmptyReplay, buffer.sample(&r1));
    for (0..5) |i| buffer.append(.{ .state = .{ 0, 0 }, .next_state = .{ 1, 1 }, .action = 0, .reward = @floatFromInt(i), .terminated = false, .truncated = false });
    try std.testing.expectEqual(@as(usize, 3), buffer.count);
    for (0..100) |_| {
        const x = try buffer.sample(&r1);
        const y = try buffer.sample(&r2);
        try std.testing.expect(std.meta.eql(x, y));
        try std.testing.expect(x.reward >= 2 and x.reward <= 4);
    }
    try std.testing.expectError(error.InvalidReplayCapacity, replay.Replay(2).init(&.{}));
}
test "epsilon extremes, selected-action MSE and target synchronization" {
    var storage: [2]replay.Transition(2) = undefined;
    var agent = try Agent.init(42, &storage, .{ .batch = 1, .warmup = 1, .train_every = 1, .target_interval = 2, .epsilon_start = 0, .epsilon_end = 0, .reward_scale = 1, .rate = 0.1, .td_clip = 100 });
    @memset(&agent.online.parameters, 0);
    agent.syncTarget();
    try std.testing.expectEqual(@as(usize, 0), try agent.selectAction(&.{ 0, 0 }));
    try agent.observe(.{ .state = .{ 0, 0 }, .next_state = .{ 0, 0 }, .action = 1, .reward = 2, .terminated = true, .truncated = false });
    try std.testing.expectEqual(@as(f32, 0), agent.online.parameters[4]);
    try std.testing.expectApproxEqAbs(@as(f32, 0.2), agent.online.parameters[5], 0.000001);
    try std.testing.expectEqual(@as(f32, 0), agent.target.parameters[5]);
    try agent.observe(.{ .state = .{ 0, 0 }, .next_state = .{ 0, 0 }, .action = 1, .reward = 2, .terminated = true, .truncated = false });
    try std.testing.expectEqualSlices(f32, &agent.online.parameters, &agent.target.parameters);
    agent.options.epsilon_start = 1;
    agent.options.epsilon_end = 1;
    var counts = [_]usize{ 0, 0 };
    for (0..64) |_| counts[try agent.selectAction(&.{ 0, 0 })] += 1;
    try std.testing.expect(counts[0] > 0 and counts[1] > 0);
    const options: dqn.Options = .{ .epsilon_steps = 100 };
    try std.testing.expectEqual(options.epsilon_start, dqn.epsilon(options, 0));
    try std.testing.expectApproxEqAbs(options.epsilon_end, dqn.epsilon(options, 1000), 0.000001);
}
test "DQN reproducibility, checkpoint and invalid transitions" {
    var left: [32]replay.Transition(2) = undefined;
    var right: [32]replay.Transition(2) = undefined;
    var a = try Agent.init(9, &left, .{ .batch = 4, .warmup = 4 });
    var b = try Agent.init(9, &right, .{ .batch = 4, .warmup = 4 });
    for (0..64) |_| {
        const action = try a.selectAction(&.{ 0.1, -0.2 });
        try std.testing.expectEqual(action, try b.selectAction(&.{ 0.1, -0.2 }));
        const t: replay.Transition(2) = .{ .state = .{ 0.1, -0.2 }, .next_state = .{ 0.2, -0.1 }, .action = action, .reward = 1, .terminated = false, .truncated = true };
        try a.observe(t);
        try b.observe(t);
    }
    const encoded = a.online.encode();
    const second = b.online.encode();
    try std.testing.expectEqualSlices(u8, &encoded, &second);
    var loaded = Agent.T.init(0);
    try loaded.decode(&encoded);
    try std.testing.expectEqualSlices(f32, &a.online.parameters, &loaded.parameters);
    try std.testing.expectError(error.NonFiniteState, a.selectAction(&.{ std.math.nan(f32), 0 }));
    a.online.parameters[5] = std.math.inf(f32);
    try std.testing.expectError(error.DivergedQ, a.selectAction(&.{ 0, 0 }));
    try std.testing.expectError(error.InvalidTransition, b.observe(.{ .state = .{ 0, 0 }, .next_state = .{ 0, 0 }, .action = 2, .reward = 1, .terminated = false, .truncated = false }));
    try std.testing.expectError(error.InvalidDqnOptions, (dqn.Options{ .gamma = std.math.nan(f32) }).validate());
}

test "centered action head preserves policy without mutating checkpoint" {
    var model = Agent.T.init(42);
    model.parameters = .{ 10, 12, 14, 16, 20, 22 };
    const original = model.encode();
    const centered = @import("policy.zig").centeredActionHead(S, &model);
    const after = model.encode();
    try std.testing.expectEqualSlices(u8, &original, &after);
    for ([_][2]f32{ .{ 0, 0 }, .{ 1, -1 }, .{ -1, -1 }, .{ 1, 1 } }) |input| {
        const raw = model.predict(&input);
        const scores = centered.predict(&input);
        try std.testing.expectEqual(try dqn.greedy(&raw), try dqn.greedy(&scores));
        try std.testing.expectApproxEqAbs(raw[0] - raw[1], scores[0] - scores[1], 0.00001);
        try std.testing.expectApproxEqAbs(@as(f32, 0), scores[0] + scores[1], 0.00001);
    }
}
