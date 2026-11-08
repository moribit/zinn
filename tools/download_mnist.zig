const std = @import("std");
const z = @import("zinn");
const progress = z.host.progress;
const download = z.host.download;
pub fn main(init: std.process.Init) !void {
    const parsed = try progress.cli(init);
    const args = parsed.args;
    if (args.len != 2 and !(args.len == 3 and std.mem.eql(u8, args[2], "--force"))) return error.ExpectedDirectoryAndOptionalForce;
    const force = args.len == 3;
    var renderer = progress.Renderer.init(init, parsed.mode);
    defer renderer.deinit();
    const observer = renderer.observer();
    var overall: progress.Task = .{ .observer = observer, .name = "MNIST", .total = 4, .unit = "files" };
    observer.emit(.{ .name = "MNIST", .kind = .started, .total = 4, .unit = "files" });
    var cached: usize = 0;
    var downloaded: usize = 0;
    errdefer overall.fail("operation failed");
    try std.Io.Dir.cwd().createDirPath(init.io, args[1]);
    var client: std.http.Client = .{ .allocator = init.gpa, .io = init.io };
    defer client.deinit();
    for (download.specs, 0..) |spec, index| {
        const path = try std.fs.path.join(init.arena.allocator(), &.{ args[1], spec.name });
        if (!force) {
            const reuse = download.reusable(init.gpa, init.io, .cwd(), path, spec) catch |err| blk: {
                std.debug.print("invalid cached MNIST file {s}: {s}; downloading replacement\n", .{ path, @errorName(err) });
                break :blk false;
            };
            if (reuse) {
                const stat = try std.Io.Dir.cwd().statFile(init.io, path, .{});
                observer.emit(.{ .name = spec.name, .kind = .completed, .detail = "cached", .unit = "B", .done = stat.size, .total = stat.size });
                cached += 1;
                overall.update(index + 1, &.{});
                continue;
            }
        }
        const url = try std.fmt.allocPrint(init.arena.allocator(), "https://storage.googleapis.com/cvdf-datasets/mnist/{s}", .{spec.name});
        var stage: progress.Task = .{ .observer = observer, .name = spec.name, .total = null, .unit = "B" };
        observer.emit(.{ .name = spec.name, .kind = .started, .unit = "B" });
        errdefer stage.fail("operation failed");
        var request = try client.request(.GET, try std.Uri.parse(url), .{ .headers = .{ .accept_encoding = .{ .override = "identity" } } });
        defer request.deinit();
        try request.sendBodiless();
        var redirect_buffer: [8192]u8 = undefined;
        var response = try request.receiveHead(&redirect_buffer);
        if (response.head.status != .ok) {
            std.debug.print("MNIST {s}: HTTP {d}\n", .{ spec.name, @backingInt(response.head.status) });
            return error.HttpDownloadFailed;
        }
        try download.checkResponse(response.head.status, response.head.content_encoding);
        const length = response.head.content_length;
        stage.terminal = true; // The body transfer owns completion/failure now.
        var buffer: [64 * 1024]u8 = undefined;
        _ = download.transferContinuing(init.gpa, init.io, .cwd(), path, spec, response.reader(&buffer), length, observer) catch |err| {
            std.debug.print("MNIST {s}: download/validation failed: {s}; destination was not replaced\n", .{ spec.name, @errorName(err) });
            return err;
        };
        downloaded += 1;
        overall.update(index + 1, &.{});
    }
    overall.finishWithMetrics(&.{ .{ .name = "downloaded", .value = @floatFromInt(downloaded) }, .{ .name = "cached", .value = @floatFromInt(cached) } });
}
