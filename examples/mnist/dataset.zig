const std = @import("std");
const z = @import("zinn");
pub fn read(init: std.process.Init, path: []const u8) ![]u8 {
    const a = init.arena.allocator();
    const bytes = try std.Io.Dir.cwd().readFileAlloc(init.io, path, a, .limited(64 * 1024 * 1024));
    if (std.mem.endsWith(u8, path, ".gz")) return z.data.unpackGzip(a, bytes, 64 * 1024 * 1024);
    return bytes;
}
pub fn load(comptime T: type, init: std.process.Init, images_path: []const u8, labels_path: []const u8, limit: usize) ![]T.Sample {
    const options = @import("dataset_options");
    if (options.csv) {
        const samples = try z.data.csv(T, init.arena.allocator(), try read(init, images_path), options.csv_header);
        return samples[0..@min(limit, samples.len)];
    } else {
        const images = try z.data.IdxImages.init(try read(init, images_path));
        const labels = try z.data.IdxLabels.init(try read(init, labels_path));
        return z.data.mnistProcessed(T, init.arena.allocator(), images, labels, limit, if (options.nearest) .nearest else .area);
    }
}

pub fn partition(comptime T: type, samples: []T.Sample) !struct { training: []T.Sample, validation: []const T.Sample } {
    const options = @import("dataset_options");
    const count = if (options.fixture and options.validation_count >= samples.len) @max(1, samples.len / 10) else options.validation_count;
    const result = try z.fit.split(T.Sample, samples, count, options.split_seed);
    return .{ .training = result.training, .validation = result.validation };
}
