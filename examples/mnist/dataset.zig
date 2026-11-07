const std = @import("std");
const z = @import("zinn");
pub fn read(init: std.process.Init, path: []const u8) ![]u8 {
    const a = init.arena.allocator();
    const bytes = try std.Io.Dir.cwd().readFileAlloc(init.io, path, a, .limited(64 * 1024 * 1024));
    if (std.mem.endsWith(u8, path, ".gz")) return z.data.unpackGzip(a, bytes, 64 * 1024 * 1024);
    return bytes;
}
pub fn load(comptime T: type, init: std.process.Init, images_path: []const u8, labels_path: []const u8, limit: usize) ![]T.Sample {
    const images = try z.data.IdxImages.init(try read(init, images_path));
    const labels = try z.data.IdxLabels.init(try read(init, labels_path));
    return z.data.mnist(T, init.arena.allocator(), images, labels, limit);
}
