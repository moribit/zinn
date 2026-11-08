//! Presentation-only launcher. The child build owns the cacheable training Run;
//! a separate journal permits live stderr without changing its cache policy.
const std = @import("std");
fn wait(io: std.Io, child: *std.process.Child, done: *std.atomic.Value(bool)) !std.process.Child.Term {
    defer done.store(true, .release);
    return child.wait(io);
}
fn drain(io: std.Io, path: []const u8, offset: *u64, visible: bool) !void {
    const file = std.Io.Dir.cwd().openFile(io, path, .{}) catch |err| switch (err) {
        error.FileNotFound => return,
        else => return err,
    };
    defer file.close(io);
    var buffer: [4096]u8 = undefined;
    while (true) {
        var vectors = [_][]u8{&buffer};
        const n = try file.readPositional(io, &vectors, offset.*);
        if (n == 0) return;
        offset.* += n;
        if (visible) std.Io.File.stderr().writeStreamingAll(io, buffer[0..n]) catch {};
    }
}
pub fn main(init: std.process.Init) !void {
    const a = init.arena.allocator();
    const args = try init.minimal.args.toSlice(a);
    if (args.len < 9) return error.InvalidTrainingLauncherArguments;
    const visible = !std.mem.eql(u8, args[1], "off");
    const journal = args[2];
    const prefix = args[3];
    const model = args[4];
    const checkpoint = args[5];
    const receipt_path = try std.fs.path.join(a, &.{ prefix, "reports", try std.fmt.allocPrint(a, "{s}-training-receipt.txt", .{model}) });
    const log = try std.fs.path.join(a, &.{ journal, "live.log" });
    try std.Io.Dir.cwd().createDirPath(init.io, journal);
    const lock_path = try std.fs.path.join(a, &.{ journal, "lock" });
    const lock = try std.Io.Dir.cwd().createFile(init.io, lock_path, .{ .truncate = false });
    defer lock.close(init.io);
    try lock.lock(init.io, .exclusive);
    defer lock.unlock(init.io);
    var nonce: [16]u8 = undefined;
    init.io.random(&nonce);
    const token = std.fmt.hex(@as(u128, @bitCast(nonce)));
    try std.Io.Dir.cwd().writeFile(init.io, .{ .sub_path = try std.fs.path.join(a, &.{ journal, "session" }), .data = &token });
    try std.Io.Dir.cwd().writeFile(init.io, .{ .sub_path = log, .data = "" });
    if (visible) std.debug.print("training {s}: checking build cache\n", .{model});
    var env: std.process.Environ.Map = .init(a);
    for (init.environ_map.keys(), init.environ_map.values()) |key, value| {
        if (!std.mem.eql(u8, key, "ZIG_PROGRESS")) try env.put(key, value);
    }
    try env.put("TERM", "dumb");
    var child = try std.process.spawn(init.io, .{ .argv = args[6..], .environ_map = &env });
    defer child.kill(init.io);
    var done: std.atomic.Value(bool) = .init(false);
    var future = try std.Io.concurrent(init.io, wait, .{ init.io, &child, &done });
    errdefer _ = future.cancel(init.io) catch {};
    var offset: u64 = 0;
    var polls: usize = 0;
    while (!done.load(.acquire)) {
        try drain(init.io, log, &offset, visible);
        polls += 1;
        if (visible and offset == 0 and polls == 50) std.debug.print("training {s}: preparing artifacts (cache check / compilation)\n", .{model});
        try std.Io.sleep(init.io, .fromMilliseconds(100), .awake);
    }
    const term = try future.await(init.io);
    try drain(init.io, log, &offset, visible);
    switch (term) {
        .exited => |code| if (code != 0) return error.TrainingBuildFailed,
        else => return error.TrainingBuildFailed,
    }
    const receipt = try std.Io.Dir.cwd().readFileAlloc(init.io, receipt_path, a, .limited(128));
    if (visible) {
        const executed = std.mem.eql(u8, receipt, &token);
        std.debug.print("{s} {s}\n  checkpoint: {s}/{s}\n  log: {s}/reports/{s}-training-progress.log\n", .{ if (executed) "completed" else "cached", model, prefix, checkpoint, prefix, model });
    }
}
