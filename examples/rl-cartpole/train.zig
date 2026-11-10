const std = @import("std");
const a = @import("agent.zig");
const z = @import("zinn");
const config = @import("options");
pub fn options() a.Options {
    return .{ .seed = config.seed, .episodes = config.episodes, .replay_capacity = config.replay_capacity, .dqn = .{ .rate = config.rate, .gamma = config.gamma, .epsilon_start = config.epsilon_start, .epsilon_end = config.epsilon_end, .epsilon_steps = config.epsilon_steps, .batch = config.batch, .train_every = config.train_every, .reward_scale = config.reward_scale, .target_interval = config.target_interval } };
}
pub fn main(init: std.process.Init) !void {
    const parsed = try z.host.progress.cli(init);
    const args = parsed.args;
    if (args.len != 9) return error.ExpectedCheckpointCurveReport;
    var renderer = z.host.progress.Renderer.initJournalToken(init, parsed.mode, parsed.journal, parsed.token);
    defer renderer.deinit();
    const storage = try init.arena.allocator().alloc(z.rl.Transition(4), config.replay_capacity);
    var session = try a.Session.init(options(), storage);
    const loaded = !std.mem.eql(u8, args[7], "-");
    if (loaded) {
        try session.best.decode(try std.Io.Dir.cwd().readFileAlloc(init.io, args[7], init.arena.allocator(), .limited(1024 * 1024)));
        session.agent.online = session.best;
        session.agent.syncTarget();
    }
    const random = try a.evaluate(&session.agent.online, true);
    const untrained = try a.evaluate(&session.agent.online, false);
    var curve: std.Io.Writer.Allocating = .init(init.arena.allocator());
    try curve.writer.writeAll("episode,reward,mean100,max_reward,epsilon,loss,evaluation_reward,steps,updates,successes,failures\n");
    var task = renderer.observer().task("CartPole DQN training", if (loaded) 0 else config.episodes);
    errdefer task.fail("training failed");
    while (!loaded and session.metrics.episodes < config.episodes) {
        if (try session.step()) |m| {
            try curve.writer.print("{d},{d},{d},{d},{d},{d},{d},{d},{d},{d},{d}\n", .{ m.episodes, m.reward, m.mean100, m.maximum, z.rl.dqn.epsilon(session.agent.options, session.agent.steps), session.agent.last_loss, m.evaluation, session.agent.steps, session.agent.updates, m.successes, m.failures });
            task.update(m.episodes, &.{ .{ .name = "mean100", .value = m.mean100 }, .{ .name = "reward", .value = @floatFromInt(m.reward) }, .{ .name = "evaluation", .value = m.evaluation } });
            if (parsed.mode != .off and m.episodes % 50 == 0) std.debug.print("episode={d} mean100={d:.1} eval={d:.1} epsilon={d:.3} loss={d:.4}\n", .{ m.episodes, m.mean100, m.evaluation, z.rl.dqn.epsilon(session.agent.options, session.agent.steps), session.agent.last_loss });
        }
    }
    const online = try a.evaluate(&session.agent.online, false);
    const evaluated = try a.evaluate(&session.best, false);
    var restored = a.T.init(0);
    const encoded = session.best.encode();
    try restored.decode(&encoded);
    const reload = try a.evaluate(&restored, false);
    if (!std.meta.eql(evaluated, reload)) return error.CheckpointEvaluationMismatch;
    var calibration: []a.T.Sample = undefined;
    if (!std.mem.eql(u8, args[8], "-")) {
        calibration = try z.data.csv(a.T, init.arena.allocator(), try std.Io.Dir.cwd().readFileAlloc(init.io, args[8], init.arena.allocator(), .limited(16 * 1024 * 1024)), false);
    } else {
        const count = if (loaded) 2048 else @min(2048, session.agent.replay.count);
        calibration = try init.arena.allocator().alloc(a.T.Sample, count + 1);
        if (loaded) {
            var world: a.env.Environment = .{};
            var rng = z.rl.Random.init(0xabc123);
            var episode: u32 = 0;
            _ = world.reset(0x40000000);
            for (calibration[0..count]) |*sample| {
                if (world.done) {
                    episode += 1;
                    _ = world.reset(0x40000000 + episode);
                }
                sample.* = .{ .input = try world.state.normalized(), .target = .{ 0, 0 } };
                _ = try world.step(if (rng.index(2) == 0) .left else .right);
            }
        } else for (calibration[0..count], 0..) |*sample, i| sample.* = .{ .input = session.agent.replay.storage[i * session.agent.replay.count / count].state, .target = .{ 0, 0 } };
        calibration[count] = .{ .input = .{ 1, 0, 0, 0 }, .target = .{ 0, 0 } };
    }
    const raw_quantized = try @import("evaluation.zig").Q.calibrate(&session.best, calibration);
    const uncentered_integer = try @import("evaluation.zig").evaluateInteger(&raw_quantized, 0xc0000000);
    const uncentered_agreement = try @import("evaluation.zig").agreement(&session.best, &raw_quantized);
    const centered = z.rl.centeredActionHead(a.S, &session.best);
    const centered_float = try a.evaluate(&centered, false);
    const quantized = try @import("evaluation.zig").Q.calibrate(&centered, calibration);
    const integer = try @import("evaluation.zig").evaluateInteger(&quantized, 0xc0000000);
    const agreement = try @import("evaluation.zig").agreement(&session.best, &quantized);
    var source: std.Io.Writer.Allocating = .init(init.arena.allocator());
    try quantized.writeSource(&source.writer);
    try quantized.writeVerification(&source.writer, calibration[0..@min(128, calibration.len)]);
    try std.Io.Dir.cwd().writeFile(init.io, .{ .sub_path = args[4], .data = source.written() });
    const metadata = try std.json.Stringify.valueAlloc(init.arena.allocator(), .{ .schema_version = @as(u32, 1), .task = "cartpole_dqn", .model_id = quantized.modelId(), .input_scale = quantized.scales[0], .output_scale = quantized.scales[a.S.layer_count], .state_divisors = [_]f32{ 2.4, 3, a.env.angle_limit, 3.5 }, .normalization = "divide then clamp [-1,1]", .reward_scale = session.agent.options.reward_scale, .q_centered = true, .output_representation = "centered action scores; not absolute return Q", .calibration_count = calibration.len, .parameter_bytes = 352 + 34 * 4, .workspace_bytes = 32, .hardware_measured = false }, .{});
    try std.Io.Dir.cwd().writeFile(init.io, .{ .sub_path = args[5], .data = metadata });
    var csv: std.Io.Writer.Allocating = .init(init.arena.allocator());
    for (calibration) |sample| {
        const q = session.best.predict(&sample.input);
        try csv.writer.print("{d},{d},{d},{d},{d}\n", .{ try z.rl.dqn.greedy(&q), sample.input[0], sample.input[1], sample.input[2], sample.input[3] });
    }
    try std.Io.Dir.cwd().writeFile(init.io, .{ .sub_path = args[6], .data = csv.written() });
    const report = try std.json.Stringify.valueAlloc(init.arena.allocator(), .{ .seed = session.best.seed, .loaded_checkpoint = loaded, .options = options(), .random = random, .untrained = if (loaded) @as(?a.Evaluation, null) else untrained, .float = evaluated, .integer = integer, .uncentered_integer = uncentered_integer, .uncentered_agreement = uncentered_agreement, .centered_float = centered_float, .agreement = agreement, .final_online = online, .best_episode = if (loaded) @as(?usize, null) else session.metrics.best_episode, .best_development_reward = if (loaded) @as(?f32, null) else session.metrics.best_evaluation, .reloaded = reload, .training_steps = session.agent.steps, .updates = session.agent.updates, .recent100 = session.metrics.mean100, .training_successes = session.metrics.successes, .training_failures = session.metrics.failures, .replay_bytes = storage.len * @sizeOf(z.rl.Transition(4)), .parameter_count = a.S.parameter_count }, .{});
    try std.Io.Dir.cwd().writeFile(init.io, .{ .sub_path = args[1], .data = &encoded });
    try std.Io.Dir.cwd().writeFile(init.io, .{ .sub_path = args[2], .data = curve.written() });
    try std.Io.Dir.cwd().writeFile(init.io, .{ .sub_path = args[3], .data = report });
    task.finish();
    try z.host.progress.writeSummary(init, parsed, .{ .kind = .train, .structure = "4 -> dense(16) -> dense(16) -> Q(2)", .note = "DQN policy checkpoint selected on development episodes; see RL rollout report (not classification accuracy)." });
    try z.host.progress.saveReceipt(init, parsed);
    std.debug.print("int8 mean={d:.1}, action agreement={d:.2}%\n", .{ integer.mean, agreement.rate });
    std.debug.print("CartPole seed={d}: random={d:.1}, untrained={d:.1}, trained={d:.1}, max={d}, success={d}/50\n", .{ config.seed, random.mean, untrained.mean, evaluated.mean, evaluated.maximum, evaluated.successes });
}
