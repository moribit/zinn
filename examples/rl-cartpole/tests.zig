const std = @import("std");
const z = @import("zinn");
const e = @import("environment.zig");
const a = @import("agent.zig");
test "CartPole reset/action sequence is deterministic and left/right symmetric" {
    var x: e.Environment = .{};
    var y: e.Environment = .{};
    try std.testing.expect(std.meta.eql(x.reset(42), y.reset(42)));
    for (0..10) |i| try std.testing.expect(std.meta.eql(try x.step(if (i % 2 == 0) .left else .right), try y.step(if (i % 2 == 0) .left else .right)));
    x = .{};
    y = .{};
    const r = try x.step(.right);
    const l = try y.step(.left);
    try std.testing.expectApproxEqAbs(@as(f32, 0.19512195), r.state.x_dot, 0.000001);
    try std.testing.expectApproxEqAbs(@as(f32, -0.29268293), r.state.theta_dot, 0.000001);
    try std.testing.expectEqual(-r.state.x_dot, l.state.x_dot);
    try std.testing.expectEqual(-r.state.theta_dot, l.state.theta_dot);
    try std.testing.expectEqual(@as(f32, 1), r.reward);
}
test "physical termination, truncation and invalid state are distinct" {
    var world: e.Environment = .{ .state = .{ .x = 2.4, .x_dot = 1 } };
    const failed = try world.step(.right);
    try std.testing.expect(failed.terminated and !failed.truncated);
    try std.testing.expectError(error.EpisodeFinished, world.step(.right));
    world = .{ .steps = 499 };
    const timeout = try world.step(.right);
    try std.testing.expect(timeout.truncated and !timeout.terminated);
    world = .{ .state = .{ .theta = e.angle_limit, .theta_dot = 1 } };
    try std.testing.expect((try world.step(.left)).terminated);
    world = .{ .state = .{ .x = std.math.nan(f32) } };
    try std.testing.expectError(error.NonFiniteState, world.step(.left));
    try std.testing.expectEqual(@as(usize, 0), world.steps);
    try std.testing.expectError(error.NonFiniteState, world.state.normalized());
}
test "training chunks and checkpoint reload do not change numerical results" {
    var sa: [512]z.rl.Transition(4) = undefined;
    var sb: [512]z.rl.Transition(4) = undefined;
    const options: a.Options = .{ .episodes = 100, .replay_capacity = 512 };
    var one = try a.Session.init(options, &sa);
    var chunks = try a.Session.init(options, &sb);
    for (0..1000) |_| {
        _ = try one.step();
    }
    for (0..10) |_| for (0..100) |_| {
        _ = try chunks.step();
    };
    const first = one.agent.online.encode();
    const second = chunks.agent.online.encode();
    try std.testing.expectEqualSlices(u8, &first, &second);
    try std.testing.expect(std.meta.eql(one.metrics, chunks.metrics));
    var loaded = a.T.init(0);
    try loaded.decode(&first);
    const input = try one.world.state.normalized();
    try std.testing.expectEqualSlices(f32, &one.agent.online.predict(&input), &loaded.predict(&input));
}
