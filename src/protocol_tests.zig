const std = @import("std");
test "CRC16 CCITT-FALSE published check vector" {
    try std.testing.expectEqual(@as(u16, 0x29b1), @import("protocol.zig").crc("123456789"));
}
const p = @import("protocol.zig");
test "framed input supports partial receive, corruption, timeout and resynchronization" {
    var out: [18]u8 = undefined;
    const bytes = try p.request(&out, .infer, 17, 42, &.{ -128, 0, 127, -1 });
    var receiver = p.Receiver(4).init(42, 10, 100);
    for (bytes[0 .. bytes.len - 1], 0..) |byte, i| try std.testing.expect(receiver.feed(byte, @intCast(i)) == .none);
    const result = receiver.feed(bytes[bytes.len - 1], 17);
    try std.testing.expectEqual(@as(u16, 17), result.request.sequence);
    try std.testing.expectEqualSlices(i8, &.{ -128, 0, 127, -1 }, &receiver.input);
    out[17] ^= 1;
    var event: p.Event = .none;
    for (out, 0..) |byte, i| event = receiver.feed(byte, @intCast(30 + i));
    try std.testing.expectEqual(p.Status.bad_crc, event.failure.status);
    _ = receiver.feed('Z', 100);
    _ = receiver.feed('I', 101);
    _ = receiver.feed(1, 102);
    try std.testing.expectEqual(p.Status.timeout, receiver.poll(112).failure.status);
    _ = try p.request(&out, .infer, 18, 42, &.{ 1, 2, 3, 4 });
    for (out, 0..) |byte, i| event = receiver.feed(byte, @intCast(120 + i));
    try std.testing.expect(event == .request);
}
test "framing rejects invalid length and model and validates response CRC" {
    var out: [18]u8 = undefined;
    _ = try p.request(&out, .infer, 1, 99, &.{ 1, 2, 3, 4 });
    var receiver = p.Receiver(4).init(42, 10, 100);
    var event: p.Event = .none;
    for (out[0..12], 0..) |byte, i| event = receiver.feed(byte, @intCast(i));
    try std.testing.expectEqual(p.Status.wrong_model, event.failure.status);
    out[6] = 42;
    out[10] = 255;
    out[11] = 255;
    for (out[0..12], 0..) |byte, i| event = receiver.feed(byte, @intCast(20 + i));
    try std.testing.expectEqual(p.Status.bad_length, event.failure.status);
    var answer: [68]u8 = undefined;
    const encoded = try p.response(&answer, .infer, 1, 42, .{ .class = 2, .min = 3, .median = 4, .max = 5, .iterations = 9, .workspace = 490, .input_len = 256, .adapter_init = 16, .transfer = 200, .preprocess = 0 }, &.{ -1, 0, 127 });
    const decoded = try p.decodeResponse(encoded);
    try std.testing.expectEqual(@as(u8, 2), decoded.class);
    try std.testing.expectEqual(@as(u32, 4), decoded.median);
    try std.testing.expectEqual(@as(u16, 9), decoded.iterations);
    try std.testing.expectEqual(@as(u16, 490), decoded.workspace);
    try std.testing.expectEqual(@as(u16, 256), decoded.input_len);
    try std.testing.expectEqual(@as(u32, 16), decoded.adapter_init);
    try std.testing.expectEqual(@as(u32, 200), decoded.transfer);
    answer[15] ^= 1;
    try std.testing.expectError(error.InvalidResponse, p.decodeResponse(encoded));
}
test "arbitrary byte streams remain bounded and info has no input payload" {
    var receiver = p.Receiver(256).init(42, 10, 100);
    var rng: u32 = 4;
    for (0..65536) |i| {
        rng = rng *% 1664525 +% 1013904223;
        _ = receiver.feed(@truncate(rng >> 16), @intCast(i));
    }
    var frame: [14]u8 = undefined;
    const bytes = try p.request(&frame, .info, 23, 0, &.{});
    receiver.reset();
    var result: p.Event = .none;
    for (bytes, 0..) |byte, i| result = receiver.feed(byte, @intCast(70000 + i));
    try std.testing.expectEqual(p.Opcode.info, result.request.opcode);
}

test "timer wrap and total-frame deadline preserve bounded receive" {
    var bytes: [18]u8 = undefined;
    _ = try p.request(&bytes, .benchmark, 2, 42, &.{ 1, 2, 3, 4 });
    var receiver = p.Receiver(4).init(42, 10, 100);
    var event: p.Event = .none;
    for (bytes, 0..) |byte, i| event = receiver.feed(byte, 0xfffffff8 +% @as(u32, @intCast(i)));
    try std.testing.expectEqual(p.Opcode.benchmark, event.request.opcode);
    receiver.reset();
    for (bytes[0..13], 0..) |byte, i| event = receiver.feed(byte, @intCast(1000 + i * 9));
    try std.testing.expect(event == .failure);
    try std.testing.expectEqual(p.Status.timeout, event.failure.status);
    try std.testing.expectError(error.InvalidRequestLength, p.request(&bytes, .info, 0, 42, &.{1}));
}
