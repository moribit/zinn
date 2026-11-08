//! Bounded body streaming and validated atomic publication; no HTTP/network required for tests.
const std = @import("std");
const data = @import("../data.zig");
const progress = @import("progress.zig");
pub const Spec = struct { name: []const u8, count: usize, images: bool, md5: ?[]const u8 = null };
// Published MNIST resource digests (torchvision MNIST resources); reference
// facts only, no dependency or upstream implementation is imported.
pub const specs = [_]Spec{
    .{ .name = "train-images-idx3-ubyte.gz", .count = 60000, .images = true, .md5 = "f68b3c2dcbeaaa9fbdd348bbdeb94873" },
    .{ .name = "train-labels-idx1-ubyte.gz", .count = 60000, .images = false, .md5 = "d53e105ee54ea40749a09fcbcd1e9432" },
    .{ .name = "t10k-images-idx3-ubyte.gz", .count = 10000, .images = true, .md5 = "9fb629c4189551a2d022fa330f9573f3" },
    .{ .name = "t10k-labels-idx1-ubyte.gz", .count = 10000, .images = false, .md5 = "ec29112dd5afa0611ce80d1b7f02629c" },
};
pub const max_compressed = 32 * 1024 * 1024;
pub fn checkResponse(status: std.http.Status, encoding: std.http.ContentEncoding) !void {
    if (status != .ok) return error.HttpDownloadFailed;
    if (encoding != .identity) return error.UnexpectedHttpContentEncoding;
}
pub fn validate(a: std.mem.Allocator, bytes: []const u8, spec: Spec) !void {
    const unpacked = try data.unpackGzip(a, bytes, 64 * 1024 * 1024);
    defer a.free(unpacked);
    if (spec.images) {
        const images = try data.IdxImages.init(unpacked);
        if (images.count != spec.count or images.height != 28 or images.width != 28) return error.UnexpectedMnistShape;
    } else {
        const labels = try data.IdxLabels.init(unpacked);
        if (labels.values.len != spec.count) return error.UnexpectedMnistCount;
        for (labels.values) |label| if (label > 9) return error.InvalidLabel;
    }
    if (spec.md5) |expected| {
        var digest: [16]u8 = undefined;
        std.crypto.hash.Md5.hash(bytes, &digest, .{});
        const hex = std.fmt.bytesToHex(digest, .lower);
        if (!std.mem.eql(u8, &hex, expected)) return error.DatasetChecksumMismatch;
    }
}
/// False only for a missing destination. Corruption is an explicit error.
pub fn reusable(a: std.mem.Allocator, io: std.Io, dir: std.Io.Dir, path: []const u8, spec: Spec) !bool {
    const bytes = dir.readFileAlloc(io, path, a, .limited(max_compressed)) catch |err| switch (err) {
        error.FileNotFound => return false,
        else => return err,
    };
    defer a.free(bytes);
    try validate(a, bytes, spec);
    return true;
}
pub fn transfer(a: std.mem.Allocator, io: std.Io, dir: std.Io.Dir, path: []const u8, spec: Spec, reader: *std.Io.Reader, content_length: ?u64, observer: progress.Observer) !u64 {
    var task = observer.task(spec.name, content_length);
    task.unit = "B";
    errdefer task.fail("operation failed");
    if (content_length) |length| if (length > max_compressed) return error.DownloadTooLarge;
    var atomic = try dir.createFileAtomic(io, path, .{ .replace = true });
    defer atomic.deinit(io);
    var buffer: [64 * 1024]u8 = undefined;
    var received: u64 = 0;
    while (true) {
        // Read what is available; do not wait to fill 64KiB before notifying
        // a slow transfer. In Reader.readVec, zero alone is not EOF.
        var vectors = [_]([]u8){&buffer};
        const n = reader.readVec(&vectors) catch |err| switch (err) {
            error.EndOfStream => break,
            else => return err,
        };
        if (n == 0) continue;
        if (n > max_compressed - received) return error.DownloadTooLarge;
        try atomic.file.writeStreamingAll(io, buffer[0..n]);
        received += n;
        task.update(received, &.{});
    }
    if (content_length) |length| if (received != length) return error.DownloadTruncated;
    // Atomic replacement temporaries are write-only on macOS; reopen the named
    // temporary for validation rather than assuming the writer handle is readable.
    try atomic.file.sync(io);
    const temporary_name = std.fmt.hex(atomic.file_basename_hex);
    const bytes = try atomic.dir.readFileAlloc(io, &temporary_name, a, .limited(max_compressed));
    defer a.free(bytes);
    try validate(a, bytes, spec);
    try atomic.replace(io);
    task.finish();
    return received;
}
test "mock HTTP body, missing length, reuse, corruption and interrupted atomic replacement" {
    const a = std.testing.allocator;
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const spec: Spec = .{ .name = "labels.gz", .count = 2, .images = false };
    const idx = "\x00\x00\x08\x01\x00\x00\x00\x02\x03\x07";
    var encoded: std.Io.Writer.Allocating = .init(a);
    defer encoded.deinit();
    try encoded.writer.writeAll("\x1f\x8b\x08\x00\x00\x00\x00\x00\x00\x03\x01");
    try encoded.writer.writeInt(u16, idx.len, .little);
    try encoded.writer.writeInt(u16, ~@as(u16, idx.len), .little);
    try encoded.writer.writeAll(idx);
    try encoded.writer.writeInt(u32, std.hash.Crc32.hash(idx), .little);
    try encoded.writer.writeInt(u32, idx.len, .little);
    const body = encoded.written();
    try std.testing.expect(!try reusable(a, io, tmp.dir, spec.name, spec));
    // Real std.http body parser, fed an in-memory HTTP response, no sockets.
    const message = try std.fmt.allocPrint(a, "HTTP/1.1 200 OK\r\nContent-Length: {d}\r\n\r\n{s}", .{ body.len, body });
    defer a.free(message);
    var wire: std.Io.Reader = .fixed(message);
    var http: std.http.Reader = .{ .in = &wire, .interface = undefined, .state = .ready, .max_head_len = 4096 };
    _ = try http.receiveHead();
    var http_buffer: [64]u8 = undefined;
    _ = try transfer(a, io, tmp.dir, spec.name, spec, http.bodyReader(&http_buffer, .none, body.len), body.len, .{});
    try std.testing.expect(try reusable(a, io, tmp.dir, spec.name, spec));
    var unknown: std.Io.Reader = .fixed(body);
    _ = try transfer(a, io, tmp.dir, "unknown.gz", spec, &unknown, null, .{});
    const unknown_message = try std.fmt.allocPrint(a, "HTTP/1.1 200 OK\r\nConnection: close\r\n\r\n{s}", .{body});
    defer a.free(unknown_message);
    var unknown_wire: std.Io.Reader = .fixed(unknown_message);
    var unknown_http: std.http.Reader = .{ .in = &unknown_wire, .interface = undefined, .state = .ready, .max_head_len = 4096 };
    _ = try unknown_http.receiveHead();
    _ = try transfer(a, io, tmp.dir, "unknown.gz", spec, unknown_http.bodyReader(&http_buffer, .none, null), null, .{});
    const chunked_message = try std.fmt.allocPrint(a, "HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n{x}\r\n{s}\r\n0\r\n\r\n", .{ body.len, body });
    defer a.free(chunked_message);
    var chunked_wire: std.Io.Reader = .fixed(chunked_message);
    var chunked_http: std.http.Reader = .{ .in = &chunked_wire, .interface = undefined, .state = .ready, .max_head_len = 4096 };
    _ = try chunked_http.receiveHead();
    _ = try transfer(a, io, tmp.dir, "unknown.gz", spec, chunked_http.bodyReader(&http_buffer, .chunked, null), null, .{});
    var truncated: std.Io.Reader = .fixed(body[0..5]);
    try std.testing.expectError(error.DownloadTruncated, transfer(a, io, tmp.dir, spec.name, spec, &truncated, body.len, .{}));
    try std.testing.expect(try reusable(a, io, tmp.dir, spec.name, spec)); // prior complete file retained
    var broken = try a.dupe(u8, body);
    defer a.free(broken);
    broken[broken.len - 8] ^= 1;
    var corrupt: std.Io.Reader = .fixed(broken);
    try std.testing.expectError(error.GzipChecksumMismatch, transfer(a, io, tmp.dir, "bad.gz", spec, &corrupt, null, .{}));
    try std.testing.expect(!try reusable(a, io, tmp.dir, "bad.gz", spec));
    try tmp.dir.writeFile(io, .{ .sub_path = "bad-cache.gz", .data = broken });
    try std.testing.expectError(error.GzipChecksumMismatch, reusable(a, io, tmp.dir, "bad-cache.gz", spec));
    var short_wire: std.Io.Reader = .fixed("HTTP/1.1 200 OK\r\nContent-Length: 999\r\n\r\nx");
    var short_http: std.http.Reader = .{ .in = &short_wire, .interface = undefined, .state = .ready, .max_head_len = 4096 };
    _ = try short_http.receiveHead();
    if (transfer(a, io, tmp.dir, "lost.gz", spec, short_http.bodyReader(&http_buffer, .none, 999), 999, .{})) |_| return error.ExpectedDisconnect else |_| {}
    try std.testing.expect(!try reusable(a, io, tmp.dir, "lost.gz", spec));
    try std.testing.expectError(error.UnexpectedMnistCount, validate(a, body, .{ .name = "wrong", .images = false, .count = 3 }));
    try std.testing.expectError(error.DatasetChecksumMismatch, validate(a, body, .{ .name = "foreign", .images = false, .count = 2, .md5 = "00000000000000000000000000000000" }));
    try std.testing.expectError(error.HttpDownloadFailed, checkResponse(.not_found, .identity));
    try std.testing.expectError(error.UnexpectedHttpContentEncoding, checkResponse(.ok, .gzip));
}
