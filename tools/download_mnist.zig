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
    var overall = observer.task("MNIST files", 4);
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
                observer.emit(.{ .name = spec.name, .kind = .completed, .detail = "reused (gzip/IDX/MD5 validated)" });
                overall.update(index + 1, &.{});
                continue;
            }
        }
        const url = try std.fmt.allocPrint(init.arena.allocator(), "https://storage.googleapis.com/cvdf-datasets/mnist/{s}", .{spec.name});
        var stage = observer.task("HTTP request", null);
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
        stage.finish();
        var buffer: [64 * 1024]u8 = undefined;
        _ = download.transfer(init.gpa, init.io, .cwd(), path, spec, response.reader(&buffer), length, observer) catch |err| {
            std.debug.print("MNIST {s}: download/validation failed: {s}; destination was not replaced\n", .{ spec.name, @errorName(err) });
            return err;
        };
        overall.update(index + 1, &.{});
    }
    overall.finish();
}
