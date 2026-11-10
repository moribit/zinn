//! Presentation-only launcher. The child build owns the cacheable training Run;
//! a separate journal permits live stderr without changing its cache policy.
const std = @import("std");
const progress = @import("progress");
const Events = struct {
    pending: [8192]u8 = undefined,
    used: usize = 0,
    offset: u64 = 0,
    state: progress.training_ui.State = .{},
    fn drain(self: *@This(), io: std.Io, path: []const u8, line: *progress.terminal_ui.Line) !void {
        const file = std.Io.Dir.cwd().openFile(io, path, .{}) catch |err| switch (err) {
            error.FileNotFound => return,
            else => return err,
        };
        defer file.close(io);
        var bytes: [4096]u8 = undefined;
        while (true) {
            var vectors = [_][]u8{&bytes};
            const count = try file.readPositional(io, &vectors, self.offset);
            if (count == 0) break;
            self.offset += count;
            for (bytes[0..count]) |byte| {
                if (byte == '\n') {
                    const parsed = std.json.parseFromSlice(progress.Event, std.heap.page_allocator, self.pending[0..self.used], .{ .allocate = .alloc_always }) catch {
                        self.used = 0;
                        continue;
                    };
                    defer parsed.deinit();
                    self.used = 0;
                    const e = parsed.value;
                    if (e.kind == .failed) {
                        line.finish();
                        std.debug.print("failed {s}: {s}\n", .{ e.name, e.detail });
                        continue;
                    }
                    if (std.mem.endsWith(u8, e.name, "training") or std.mem.eql(u8, e.unit, "batches")) {
                        const now = progress.nowNs(io);
                        self.state.update(e, now);
                        var buffer: [512]u8 = undefined;
                        const width = line.width();
                        line.drawWidth(try self.state.format(&buffer, e, now, width), width);
                        if (e.kind == .completed or e.kind == .failed) line.finish();
                    } else if (e.detail.len > 0) {
                        line.finish();
                        std.debug.print("{s}: {s}\n", .{ e.name, e.detail });
                    }
                } else if (self.used < self.pending.len) {
                    self.pending[self.used] = byte;
                    self.used += 1;
                } else self.used = 0;
            }
        }
    }
};
fn wait(io: std.Io, child: *std.process.Child, done: *std.atomic.Value(bool)) !std.process.Child.Term {
    defer done.store(true, .release);
    return child.wait(io);
}
fn drain(io: std.Io, path: []const u8, offset: *u64, visible: bool, line: ?*progress.terminal_ui.Line) !void {
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
        if (visible) {
            if (line) |display| display.finish();
            std.Io.File.stderr().writeStreamingAll(io, buffer[0..n]) catch {};
        }
    }
}
pub fn main(init: std.process.Init) !void {
    const a = init.arena.allocator();
    const args = try init.minimal.args.toSlice(a);
    if (args.len < 9) return error.InvalidTrainingLauncherArguments;
    const visible = !std.mem.eql(u8, args[1], "off");
    var line = progress.terminal_ui.Line.init(init, std.mem.eql(u8, args[1], "auto"));
    defer line.deinit();
    var events: Events = .{};
    const journal = args[2];
    const prefix = args[3];
    const model = args[4];
    const checkpoint = args[5];
    const receipt_path = try std.fs.path.join(a, &.{ prefix, "reports", try std.fmt.allocPrint(a, "{s}-training-receipt.txt", .{model}) });
    const log = try std.fs.path.join(a, &.{ journal, "live.log" });
    const event_log = try std.fs.path.join(a, &.{ journal, "events.jsonl" });
    const diagnostic_path = try std.fs.path.join(a, &.{ journal, "build.log" });
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
    try std.Io.Dir.cwd().writeFile(init.io, .{ .sub_path = event_log, .data = "" });
    const diagnostics = if (line.enabled) try std.Io.Dir.cwd().createFile(init.io, diagnostic_path, .{}) else null;
    defer if (diagnostics) |file| file.close(init.io);
    if (visible) std.debug.print("training {s}: checking build cache\n", .{model});
    var env: std.process.Environ.Map = .init(a);
    for (init.environ_map.keys(), init.environ_map.values()) |key, value| {
        if (!std.mem.eql(u8, key, "ZIG_PROGRESS")) try env.put(key, value);
    }
    try env.put("TERM", "dumb");
    var child = try std.process.spawn(init.io, .{ .argv = args[6..], .environ_map = &env, .stderr = if (diagnostics) |file| .{ .file = file } else .inherit });
    defer child.kill(init.io);
    var done: std.atomic.Value(bool) = .init(false);
    var future = try std.Io.concurrent(init.io, wait, .{ init.io, &child, &done });
    errdefer _ = future.cancel(init.io) catch {};
    var offset: u64 = 0;
    var diagnostic_offset: u64 = 0;
    var polls: usize = 0;
    while (!done.load(.acquire)) {
        try drain(init.io, log, &offset, visible and !line.enabled, null);
        if (line.enabled) try events.drain(init.io, event_log, &line);
        if (line.enabled) try drain(init.io, diagnostic_path, &diagnostic_offset, true, &line);
        polls += 1;
        if (visible and offset == 0 and polls == 50) std.debug.print("training {s}: preparing artifacts (cache check / compilation)\n", .{model});
        try std.Io.sleep(init.io, .fromMilliseconds(100), .awake);
    }
    const term = try future.await(init.io);
    try drain(init.io, log, &offset, visible and !line.enabled, null);
    if (line.enabled) try events.drain(init.io, event_log, &line);
    if (line.enabled) try drain(init.io, diagnostic_path, &diagnostic_offset, true, &line);
    line.finish();
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
