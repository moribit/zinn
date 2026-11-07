const std = @import("std");
const z = @import("root.zig");
test "CSV accepts CRLF and rejects missing, extra, quoted and nonfinite features" {
    const T = z.Trainer(z.Definition(2, &.{.{ .units = 2 }}));
    const a = std.testing.allocator;
    const rows = try z.data.csv(T, a, "label,x,y\r\n0,0.5,1\r\n1,-1,2\n", true);
    defer a.free(rows);
    try std.testing.expectEqual(@as(usize, 2), rows.len);
    try std.testing.expectEqual(@as(f32, 0.5), rows[0].input[0]);
    try std.testing.expectError(error.CsvColumnCountMismatch, z.data.csv(T, a, "0,1", false));
    try std.testing.expectError(error.CsvColumnCountMismatch, z.data.csv(T, a, "0,1,2,3", false));
    try std.testing.expectError(error.QuotedCsvUnsupported, z.data.csv(T, a, "0,\"1\",2", false));
    try std.testing.expectError(error.NonFiniteFeature, z.data.csv(T, a, "0,nan,2", false));
    try std.testing.expectError(error.InvalidLabel, z.data.csv(T, a, "2,1,2", false));
}
test "IDX exact lengths, bounds, and area preprocessing" {
    const bytes = [20]u8{ 0, 0, 8, 3, 0, 0, 0, 1, 0, 0, 0, 2, 0, 0, 0, 2, 0, 255, 255, 0 };
    const images = try z.data.IdxImages.init(&bytes);
    try std.testing.expectEqual(@as(usize, 1), images.count);
    try std.testing.expectError(error.SampleOutOfBounds, images.image(1));
    try std.testing.expectError(error.InvalidIdxSize, z.data.IdxImages.init(bytes[0..19]));
    var out: [1]f32 = undefined;
    try z.data.resizeArea(try images.image(0), 2, 2, &out, 1, 1);
    try std.testing.expectApproxEqAbs(@as(f32, 0.5), out[0], 0.000001);
    var white: [784]u8 = @splat(255);
    white[0] = 255;
    var resized: [256]f32 = undefined;
    try z.data.resizeArea(&white, 28, 28, &resized, 16, 16);
    for (resized) |v| try std.testing.expectEqual(@as(f32, 1), v);
}

test "gzip validates CRC, size, bounded expansion and trailing members" {
    const a = std.testing.allocator;
    var bytes = [26]u8{ 0x1f, 0x8b, 8, 0, 0, 0, 0, 0, 0, 3, 1, 3, 0, 0xfc, 0xff, 'a', 'b', 'c', 0, 0, 0, 0, 3, 0, 0, 0 };
    std.mem.writeInt(u32, bytes[18..22], std.hash.Crc32.hash("abc"), .little);
    const plain = try z.data.unpackGzip(a, &bytes, 100);
    defer a.free(plain);
    try std.testing.expectEqualStrings("abc", plain);
    try std.testing.expectError(error.StreamTooLong, z.data.unpackGzip(a, &bytes, 2));
    bytes[18] ^= 1;
    try std.testing.expectError(error.GzipChecksumMismatch, z.data.unpackGzip(a, &bytes, 100));
    bytes[18] ^= 1;
    var trailing: [27]u8 = undefined;
    @memcpy(trailing[0..26], &bytes);
    trailing[26] = 0;
    try std.testing.expectError(error.GzipTrailingData, z.data.unpackGzip(a, &trailing, 100));
}

test "MNIST rejects label mismatch and invalid labels outside a selected subset" {
    const T = z.Trainer(z.Definition(256, &.{.{ .units = 10 }}));
    const a = std.testing.allocator;
    const images: z.data.IdxImages = .{ .count = 2, .height = 28, .width = 28, .pixels = &@as([1568]u8, @splat(0)) };
    try std.testing.expectError(error.MnistShapeMismatch, z.data.mnist(T, a, images, .{ .values = &.{0} }, 1));
    try std.testing.expectError(error.InvalidLabel, z.data.mnist(T, a, images, .{ .values = &.{ 0, 10 } }, 1));
}
