//! Isolated experiment; does not change the production Agent/Trainer defaults.
const std = @import("std");
const z = @import("zinn");
const a = @import("agent.zig");
pub fn main(init: std.process.Init) !void {
    const allocator = init.arena.allocator();
    const args = try init.minimal.args.toSlice(allocator);
    if (args.len != 3) return error.ExpectedSeedOutput;
    const seed = try std.fmt.parseInt(u32, args[1], 10);
    inline for (.{ false, true }) |decay| {
        const storage = try allocator.alloc(z.rl.Transition(4), 10000);
        var session = try a.Session.init(.{ .seed = seed }, storage);
        var curve: std.Io.Writer.Allocating = .init(allocator);
        try curve.writer.writeAll("episode,reward,mean100,evaluation_reward,rate,steps,updates\n");
        while (session.metrics.episodes < 1000) {
            if (decay and session.agent.updates >= 40000) session.agent.options.rate = 0.005 * 0.25;
            if (try session.step()) |m| try curve.writer.print("{d},{d},{d},{d},{d},{d},{d}\n", .{ m.episodes, m.reward, m.mean100, m.evaluation, session.agent.options.rate, session.agent.steps, session.agent.updates });
        }
        const stem = if (decay) "step-decay" else "fixed";
        const csv = try std.fmt.allocPrint(allocator, "{s}/{s}.csv", .{ args[2], stem });
        try std.Io.Dir.cwd().writeFile(init.io, .{ .sub_path = csv, .data = curve.written() });
        const report = try std.json.Stringify.valueAlloc(allocator, .{ .seed = seed, .decay = decay, .metrics = session.metrics, .updates = session.agent.updates }, .{});
        try std.Io.Dir.cwd().writeFile(init.io, .{ .sub_path = try std.fmt.allocPrint(allocator, "{s}/{s}.json", .{ args[2], stem }), .data = report });
    }
}
