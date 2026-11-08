//! Synthetic host-only fit overhead; no network, accuracy claim or device access.
const std = @import("std");
const z = @import("zinn");
pub fn main(init: std.process.Init) !void {
    const S = z.Definition(256, &.{ .{ .units = 16, .activation = .relu }, .{ .units = 10 } });
    const T = z.Trainer(S);
    const a = init.arena.allocator();
    const samples = try a.alloc(T.Sample, 512);
    for (samples, 0..) |*sample, i| {
        for (&sample.input, 0..) |*v, k| v.* = @as(f32, @floatFromInt((i * 17 + k * 13) % 256)) / 255;
        @memset(&sample.target, 0);
        sample.target[i % 10] = 1;
    }
    var times: [2][5]u64 = undefined;
    var expected: [T.checkpoint_len]u8 = undefined;
    var renderer = z.host.progress.Renderer.init(init, .plain);
    defer renderer.deinit();
    // Alternate ordering across five paired trials to reduce thermal/order bias.
    for (0..5) |trial| for (0..2) |order| {
        const mode = (order + trial) % 2;
        const copy = try a.dupe(T.Sample, samples);
        var model = T.init(42);
        var curve: std.Io.Writer.Allocating = .init(a);
        const start = z.host.progress.nowNs(init.io);
        _ = try z.fit.train(T, &model, copy, &.{}, .{ .epochs = 6, .batch = 32, .observer = if (mode == 0) .{} else renderer.observer(), .model_name = "Synthetic benchmark" }, &curve.writer);
        times[mode][trial] = z.host.progress.nowNs(init.io) - start;
        if (trial == 0 and order == 0) expected = model.encode();
        if (!std.mem.eql(u8, &expected, &model.encode())) return error.ProgressChangedCheckpoint;
    };
    for (&times) |*values| std.mem.sort(u64, values, {}, std.sort.asc(u64));
    const text = try std.fmt.allocPrint(a, "mode,median_ns,min_ns,max_ns\noff,{d},{d},{d}\nplain,{d},{d},{d}\n", .{ times[0][2], times[0][0], times[0][4], times[1][2], times[1][0], times[1][4] });
    try std.Io.File.stdout().writeStreamingAll(init.io, text);
}
