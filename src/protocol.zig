//! Framed, stop-and-wait byte transport. No allocation, callbacks, floats or HAL dependency.
const std = @import("std");
pub const header_bytes = 12;
pub const metric_bytes = 44;
pub const Opcode = enum(u8) { infer = 1, info = 2, benchmark = 3 };
pub const Status = enum(u8) { ok = 0, bad_version = 1, bad_opcode = 2, bad_length = 3, wrong_model = 4, bad_crc = 5, timeout = 6, uart_error = 7 };
pub fn crcByte(previous: u16, byte: u8) u16 {
    var value = previous ^ (@as(u16, byte) << 8);
    for (0..8) |_| value = if (value & 0x8000 != 0) (value << 1) ^ 0x1021 else value << 1;
    return value;
}
pub fn crc(bytes: []const u8) u16 {
    var value: u16 = 0xffff;
    for (bytes) |byte| value = crcByte(value, byte);
    return value;
}
fn u16le(bytes: []const u8, at: usize) u16 {
    return std.mem.readInt(u16, bytes[at..][0..2], .little);
}
fn u32le(bytes: []const u8, at: usize) u32 {
    return std.mem.readInt(u32, bytes[at..][0..4], .little);
}
fn header(out: []u8, opcode: u8, sequence: u16, model: u32, len: usize) void {
    @memcpy(out[0..2], "ZI");
    out[2] = 1;
    out[3] = opcode;
    std.mem.writeInt(u16, out[4..6], sequence, .little);
    std.mem.writeInt(u32, out[6..10], model, .little);
    std.mem.writeInt(u16, out[10..12], @intCast(len), .little);
}
pub fn request(out: []u8, opcode: Opcode, sequence: u16, model: u32, input: []const i8) ![]const u8 {
    if ((opcode == .info and input.len != 0) or (opcode != .info and input.len == 0)) return error.InvalidRequestLength;
    if (input.len > 65535 or out.len < input.len + 14) return error.FrameBufferTooSmall;
    header(out, @backingInt(opcode), sequence, model, input.len);
    for (input, 0..) |v, i| out[12 + i] = @bitCast(v);
    std.mem.writeInt(u16, out[12 + input.len ..][0..2], crc(out[0 .. 12 + input.len]), .little);
    return out[0 .. input.len + 14];
}
pub const Request = struct { opcode: Opcode, sequence: u16, transfer_ticks: u32 };
pub const Failure = struct { status: Status, sequence: u16 = 0, opcode: Opcode = .infer };
pub const Event = union(enum) { none, request: Request, failure: Failure };
pub fn Receiver(comptime N: usize) type {
    if (N == 0 or N > 65535) @compileError("protocol input length must be 1..65535");
    return struct {
        const Self = @This();
        input: [N]i8 = undefined,
        bytes: [12]u8 = undefined,
        phase: enum { sync0, sync1, header, payload, crc_low, crc_high } = .sync0,
        index: u16 = 0,
        checksum: u16 = 0xffff,
        received: u16 = 0,
        started: u32 = 0,
        last: u32 = 0,
        timeout_ticks: u32,
        frame_ticks: u32,
        model_id: u32,
        pub fn init(model_id: u32, timeout_ticks: u32, frame_ticks: u32) Self {
            return .{ .model_id = model_id, .timeout_ticks = timeout_ticks, .frame_ticks = frame_ticks };
        }
        pub fn reset(self: *Self) void {
            self.phase = .sync0;
            self.index = 0;
            self.checksum = 0xffff;
        }
        fn failure(self: *Self, status: Status) Event {
            const sequence = if (self.phase == .header and self.index < 6) 0 else u16le(&self.bytes, 4);
            const op: Opcode = if (self.phase != .header or self.index >= 4) (if (self.bytes[3] == 2) .info else if (self.bytes[3] == 3) .benchmark else .infer) else .infer;
            self.reset();
            return .{ .failure = .{ .status = status, .sequence = sequence, .opcode = op } };
        }
        pub fn poll(self: *Self, now: u32) Event {
            if (self.phase != .sync0 and (now -% self.last >= self.timeout_ticks or now -% self.started >= self.frame_ticks)) {
                if (self.phase == .sync1) {
                    self.reset();
                    return .{ .failure = .{ .status = .timeout } };
                }
                return self.failure(.timeout);
            }
            return .none;
        }
        pub fn feed(self: *Self, byte: u8, now: u32) Event {
            const expired = self.poll(now);
            self.last = now;
            if (self.phase == .sync0) {
                if (byte == 'Z') {
                    self.phase = .sync1;
                    self.started = now;
                }
                return expired;
            }
            if (self.phase == .sync1) {
                if (byte == 'I') {
                    self.phase = .header;
                    self.index = 2;
                    @memcpy(self.bytes[0..2], "ZI");
                    self.checksum = crc(self.bytes[0..2]);
                } else if (byte != 'Z') self.reset();
                return .none;
            }
            switch (self.phase) {
                .header => {
                    self.bytes[self.index] = byte;
                    self.index += 1;
                    self.checksum = crcByte(self.checksum, byte);
                    if (self.index == 12) {
                        if (self.bytes[2] != 1) return self.failure(.bad_version);
                        const opcode = self.bytes[3];
                        const len = u16le(&self.bytes, 10);
                        if (opcode < 1 or opcode > 3) return self.failure(.bad_opcode);
                        if (len != (if (opcode == 2) @as(usize, 0) else N)) return self.failure(.bad_length);
                        if (u32le(&self.bytes, 6) != self.model_id and !(opcode == 2 and u32le(&self.bytes, 6) == 0)) return self.failure(.wrong_model);
                        self.index = 0;
                        self.phase = if (len == 0) .crc_low else .payload;
                    }
                },
                .payload => {
                    self.input[self.index] = @bitCast(byte);
                    self.index += 1;
                    self.checksum = crcByte(self.checksum, byte);
                    if (self.index == N) self.phase = .crc_low;
                },
                .crc_low => {
                    self.received = byte;
                    self.phase = .crc_high;
                },
                .crc_high => {
                    self.received |= @as(u16, byte) << 8;
                    if (self.received != self.checksum) return self.failure(.bad_crc);
                    const op: Opcode = if (self.bytes[3] == 1) .infer else if (self.bytes[3] == 2) .info else .benchmark;
                    const result: Request = .{ .opcode = op, .sequence = u16le(&self.bytes, 4), .transfer_ticks = now -% self.started };
                    self.reset();
                    return .{ .request = result };
                },
                else => unreachable,
            }
            return .none;
        }
    };
}
pub const Metrics = struct {
    status: Status = .ok,
    class: u8 = 255,
    iterations: u16 = 0,
    clock_hz: u32 = 0,
    overhead: u32 = 0,
    min: u32 = 0,
    median: u32 = 0,
    max: u32 = 0,
    stack_high_water: u16 = 0xffff,
    workspace: u16 = 0,
    adapter_init: u32 = 0,
    transfer: u32 = 0,
    preprocess: u32 = 0,
    input_len: u16 = 0,
};
pub fn response(out: []u8, opcode: Opcode, sequence: u16, model: u32, metrics: Metrics, logits: []const i8) ![]const u8 {
    const len = metric_bytes + logits.len;
    if (len > 65535 or out.len < len + 14) return error.FrameBufferTooSmall;
    header(out, @backingInt(opcode) | 0x80, sequence, model, len);
    const p = out[12..][0..len];
    @memset(p, 0);
    p[0] = @backingInt(metrics.status);
    p[1] = metrics.class;
    std.mem.writeInt(u16, p[2..4], metrics.iterations, .little);
    inline for (.{ .{ 4, metrics.clock_hz }, .{ 8, metrics.overhead }, .{ 12, metrics.min }, .{ 16, metrics.median }, .{ 20, metrics.max }, .{ 28, metrics.adapter_init }, .{ 32, metrics.transfer }, .{ 36, metrics.preprocess } }) |field| std.mem.writeInt(u32, p[field[0]..][0..4], field[1], .little);
    std.mem.writeInt(u16, p[24..26], metrics.stack_high_water, .little);
    std.mem.writeInt(u16, p[26..28], metrics.workspace, .little);
    std.mem.writeInt(u16, p[40..42], @intCast(logits.len), .little);
    std.mem.writeInt(u16, p[42..44], metrics.input_len, .little);
    for (logits, 0..) |v, i| p[44 + i] = @bitCast(v);
    std.mem.writeInt(u16, out[12 + len ..][0..2], crc(out[0 .. 12 + len]), .little);
    return out[0 .. 14 + len];
}
pub const Response = struct { opcode: u8, sequence: u16, model_id: u32, status: u8, class: u8, logits: []const u8, min: u32, median: u32, max: u32, overhead: u32, clock_hz: u32, stack_high_water: u16, iterations: u16, workspace: u16, adapter_init: u32, transfer: u32, preprocess: u32, input_len: u16 };
pub fn decodeResponse(bytes: []const u8) !Response {
    if (bytes.len < 14 + metric_bytes or !std.mem.eql(u8, bytes[0..3], "ZI\x01") or bytes[3] & 0x80 == 0) return error.InvalidResponse;
    if (bytes[3] & 0x7f < 1 or bytes[3] & 0x7f > 3) return error.InvalidResponse;
    const len = u16le(bytes, 10);
    if (len < metric_bytes or bytes.len != len + 14 or u16le(bytes, bytes.len - 2) != crc(bytes[0 .. bytes.len - 2])) return error.InvalidResponse;
    const p = bytes[12..][0..len];
    if (u16le(p, 40) != len - metric_bytes) return error.InvalidResponse;
    return .{ .opcode = bytes[3] & 0x7f, .sequence = u16le(bytes, 4), .model_id = u32le(bytes, 6), .status = p[0], .class = p[1], .logits = p[44..], .min = u32le(p, 12), .median = u32le(p, 16), .max = u32le(p, 20), .overhead = u32le(p, 8), .clock_hz = u32le(p, 4), .stack_high_water = u16le(p, 24), .iterations = u16le(p, 2), .workspace = u16le(p, 26), .adapter_init = u32le(p, 28), .transfer = u32le(p, 32), .preprocess = u32le(p, 36), .input_len = u16le(p, 42) };
}
