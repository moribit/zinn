const std = @import("std");
pub fn main(init: std.process.Init) !void {
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    if (args.len != 2) return error.ExpectedDirectory;
    try std.Io.Dir.cwd().createDirPath(init.io, args[1]);
    var client: std.http.Client = .{ .allocator = init.gpa, .io = init.io };
    defer client.deinit();
    const names = [_][]const u8{ "train-images-idx3-ubyte.gz", "train-labels-idx1-ubyte.gz", "t10k-images-idx3-ubyte.gz", "t10k-labels-idx1-ubyte.gz" };
    for (names) |name| {
        var body: std.Io.Writer.Allocating = .init(init.gpa);
        defer body.deinit();
        const url = try std.fmt.allocPrint(init.arena.allocator(), "https://storage.googleapis.com/cvdf-datasets/mnist/{s}", .{name});
        const response = try client.fetch(.{ .location = .{ .url = url }, .response_writer = &body.writer });
        if (response.status != .ok) return error.DownloadFailed;
        const path = try std.fs.path.join(init.arena.allocator(), &.{ args[1], name });
        try std.Io.Dir.cwd().writeFile(init.io, .{ .sub_path = path, .data = body.written() });
        std.debug.print("downloaded {s}: {d}B\n", .{ path, body.written().len });
    }
}
