//! Synthetic IDX fixtures for offline integration testing. Not MNIST accuracy data.
const std = @import("std");
fn gzip(init: std.process.Init, path: []const u8, bytes: []const u8) !void {
    var out: std.Io.Writer.Allocating = .init(init.arena.allocator());
    try out.writer.writeAll("\x1f\x8b\x08\x00\x00\x00\x00\x00\x00\x03");
    try out.writer.writeByte(1); // final uncompressed DEFLATE block
    try out.writer.writeInt(u16, @intCast(bytes.len), .little);
    try out.writer.writeInt(u16, ~@as(u16, @intCast(bytes.len)), .little);
    try out.writer.writeAll(bytes);
    try out.writer.writeInt(u32, std.hash.Crc32.hash(bytes), .little);
    try out.writer.writeInt(u32, @intCast(bytes.len), .little);
    try std.Io.Dir.cwd().writeFile(init.io, .{ .sub_path = path, .data = out.written() });
}
pub fn main(init: std.process.Init) !void {
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    if (args.len != 2) return error.ExpectedDirectory;
    try std.Io.Dir.cwd().createDirPath(init.io, args[1]);
    inline for (.{ .{ "train", 32 }, .{ "t10k", 16 } }) |split| {
        var images: [16 + split[1] * 784]u8 = @splat(0);
        std.mem.writeInt(u32, images[0..4], 2051, .big);
        std.mem.writeInt(u32, images[4..8], split[1], .big);
        std.mem.writeInt(u32, images[8..12], 28, .big);
        std.mem.writeInt(u32, images[12..16], 28, .big);
        var labels: [8 + split[1]]u8 = @splat(0);
        std.mem.writeInt(u32, labels[0..4], 2049, .big);
        std.mem.writeInt(u32, labels[4..8], split[1], .big);
        for (0..split[1]) |i| {
            labels[8 + i] = @intCast(i % 10);
            for (0..784) |pixel| images[16 + i * 784 + pixel] = if ((pixel / 28 + i) % 10 == 0 or (pixel % 28 + i / 10) % 13 == 0) 255 else 0;
        }
        const a = init.arena.allocator();
        try gzip(init, try std.fs.path.join(a, &.{ args[1], split[0] ++ "-images-idx3-ubyte.gz" }), &images);
        try gzip(init, try std.fs.path.join(a, &.{ args[1], split[0] ++ "-labels-idx1-ubyte.gz" }), &labels);
    }
}
