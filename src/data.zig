//! Host-only validated CSV/IDX inputs and deterministic image preprocessing.
const std = @import("std");
pub fn csv(comptime T: type, allocator: std.mem.Allocator, text: []const u8, header: bool) ![]T.Sample {
    var rows: std.ArrayList(T.Sample) = .empty;
    errdefer rows.deinit(allocator);
    var lines = std.mem.tokenizeScalar(u8, text, '\n');
    var first = true;
    while (lines.next()) |raw| {
        const line = std.mem.trim(u8, raw, " \r\t");
        if (line.len == 0) continue;
        if (header and first) {
            first = false;
            continue;
        }
        first = false;
        if (std.mem.indexOfScalar(u8, line, '"') != null) return error.QuotedCsvUnsupported;
        var cells = std.mem.splitScalar(u8, line, ',');
        const label = std.fmt.parseInt(usize, std.mem.trim(u8, cells.next().?, " \t"), 10) catch return error.InvalidLabel;
        var sample: T.Sample = undefined;
        if (label >= sample.target.len) return error.InvalidLabel;
        @memset(&sample.target, 0);
        sample.target[label] = 1;
        for (&sample.input) |*value| {
            const cell = cells.next() orelse return error.CsvColumnCountMismatch;
            value.* = std.fmt.parseFloat(f32, std.mem.trim(u8, cell, " \t")) catch return error.InvalidFeature;
            if (!std.math.isFinite(value.*)) return error.NonFiniteFeature;
        }
        if (cells.next() != null) return error.CsvColumnCountMismatch;
        try rows.append(allocator, sample);
    }
    if (rows.items.len == 0) return error.EmptyDataset;
    return rows.toOwnedSlice(allocator);
}
fn be(bytes: []const u8, offset: usize) u32 {
    return std.mem.readInt(u32, bytes[offset..][0..4], .big);
}
pub const IdxImages = struct {
    count: usize,
    height: usize,
    width: usize,
    pixels: []const u8,
    pub fn init(bytes: []const u8) !IdxImages {
        if (bytes.len < 16 or be(bytes, 0) != 2051) return error.InvalidIdxImages;
        const n = be(bytes, 4);
        const h = be(bytes, 8);
        const w = be(bytes, 12);
        if (n == 0 or h == 0 or w == 0) return error.InvalidIdxDimensions;
        const size = @mulWithOverflow(@as(u64, n) * h, @as(u64, w));
        if (size[1] != 0 or size[0] != bytes.len - 16) return error.InvalidIdxSize;
        return .{ .count = n, .height = h, .width = w, .pixels = bytes[16..] };
    }
    pub fn image(self: IdxImages, index: usize) ![]const u8 {
        if (index >= self.count) return error.SampleOutOfBounds;
        const size = self.height * self.width;
        return self.pixels[index * size ..][0..size];
    }
};
pub const IdxLabels = struct {
    values: []const u8,
    pub fn init(bytes: []const u8) !IdxLabels {
        if (bytes.len < 8 or be(bytes, 0) != 2049) return error.InvalidIdxLabels;
        if (be(bytes, 4) == 0 or be(bytes, 4) != bytes.len - 8) return error.InvalidIdxSize;
        return .{ .values = bytes[8..] };
    }
};
pub fn unpackGzip(allocator: std.mem.Allocator, bytes: []const u8, limit: usize) ![]u8 {
    var reader: std.Io.Reader = .fixed(bytes);
    var decompressor: std.compress.flate.Decompress = .init(&reader, .gzip, &.{});
    const result = try decompressor.reader.allocRemaining(allocator, .limited(limit));
    errdefer allocator.free(result);
    const metadata = decompressor.container_metadata.gzip;
    if (metadata.count != result.len or metadata.crc != std.hash.Crc32.hash(result)) return error.GzipChecksumMismatch;
    if (reader.seek != bytes.len) return error.GzipTrailingData;
    return result;
}
/// Area-weighted resize in integer grid coordinates, followed by /255 normalization.
pub fn resizeArea(pixels: []const u8, height: usize, width: usize, output: []f32, out_h: usize, out_w: usize) !void {
    if (height == 0 or width == 0 or out_h == 0 or out_w == 0 or height > 4096 or width > 4096 or out_h > 4096 or out_w > 4096) return error.InvalidImageShape;
    if (pixels.len != height * width or output.len != out_h * out_w) return error.InvalidImageShape;
    for (0..out_h) |oy| for (0..out_w) |ox| {
        var sum: u64 = 0;
        const y0 = oy * height;
        const y1 = (oy + 1) * height;
        const x0 = ox * width;
        const x1 = (ox + 1) * width;
        for (y0 / out_h..@min(height, (y1 + out_h - 1) / out_h)) |sy| {
            const dy = @min(y1, (sy + 1) * out_h) - @max(y0, sy * out_h);
            for (x0 / out_w..@min(width, (x1 + out_w - 1) / out_w)) |sx| {
                const dx = @min(x1, (sx + 1) * out_w) - @max(x0, sx * out_w);
                sum += @as(u64, pixels[sy * width + sx]) * dx * dy;
            }
        }
        output[oy * out_w + ox] = @as(f32, @floatFromInt(sum)) / @as(f32, @floatFromInt(255 * height * width));
    };
}
pub fn mnist(comptime T: type, allocator: std.mem.Allocator, images: IdxImages, labels: IdxLabels, maximum: usize) ![]T.Sample {
    if (images.height != 28 or images.width != 28 or images.count != labels.values.len) return error.MnistShapeMismatch;
    if (maximum == 0) return error.EmptyDataset;
    // Validate all labels, even if a subset is requested.
    for (labels.values) |label| if (label > 9) return error.InvalidLabel;
    const result = try allocator.alloc(T.Sample, @min(maximum, images.count));
    errdefer allocator.free(result);
    for (result, 0..) |*sample, i| {
        if (sample.input.len != 256 or sample.target.len != 10) @compileError("MNIST expects 16x16 input and 10 classes");
        try resizeArea(try images.image(i), 28, 28, &sample.input, 16, 16);
        @memset(&sample.target, 0);
        sample.target[labels.values[i]] = 1;
    }
    return result;
}
