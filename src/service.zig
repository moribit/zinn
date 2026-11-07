//! Comptime transport adapter; all request/response/workspace storage is explicit.
const protocol = @import("protocol.zig");
pub fn Service(comptime M: type, comptime Board: type) type {
    if (M.output_len > 255) @compileError("classification protocol supports at most 255 classes");
    return struct {
        const Self = @This();
        receiver: protocol.Receiver(M.input_len),
        workspace: M.Workspace = undefined,
        output: [M.output_len]i8 = undefined,
        tx: [14 + protocol.metric_bytes + M.output_len]u8 = undefined,
        samples: [9]u32 = undefined,
        model_id: u32,
        adapter_init: u32,
        pub fn init(self: *Self, model_id: u32) void {
            self.adapter_init = Board.init();
            self.model_id = model_id;
            self.receiver = protocol.Receiver(M.input_len).init(model_id, Board.clock_hz / 20, Board.clock_hz / 4);
        }
        fn send(self: *Self, op: protocol.Opcode, sequence: u16, status: protocol.Status, transfer: u32) void {
            var metrics: protocol.Metrics = .{ .status = status, .clock_hz = Board.clock_hz, .workspace = M.workspace_bytes, .input_len = M.input_len, .adapter_init = self.adapter_init, .transfer = transfer };
            var logits: []const i8 = &.{};
            if (status == .ok and op != .info) {
                if (op == .benchmark) {
                    const summary = @import("benchmark.zig").measure(M, Board, &self.receiver.input, &self.output, &self.workspace, &self.samples);
                    metrics.overhead = summary.overhead;
                    metrics.min = summary.min;
                    metrics.median = summary.median;
                    metrics.max = summary.max;
                    metrics.iterations = summary.iterations;
                } else {
                    M.infer(&self.receiver.input, &self.output, &self.workspace);
                    // Production infer deliberately has no timing instrumentation.
                }
                var best: usize = 0;
                for (self.output, 0..) |value, i| {
                    if (value > self.output[best]) best = i;
                }
                metrics.class = @intCast(best);
                logits = &self.output;
            }
            metrics.stack_high_water = Board.highWater();
            const frame = protocol.response(&self.tx, op, sequence, self.model_id, metrics, logits) catch unreachable;
            _ = Board.write(frame);
        }
        pub fn step(self: *Self) void {
            const incoming = Board.read();
            const event: protocol.Event = switch (incoming) {
                .none => self.receiver.poll(Board.now()),
                .byte => |byte| self.receiver.feed(byte, Board.now()),
                .failure => blk: {
                    self.receiver.reset();
                    break :blk .{ .failure = .{ .status = .uart_error } };
                },
            };
            switch (event) {
                .none => {},
                .failure => |failure| self.send(failure.opcode, failure.sequence, failure.status, 0),
                .request => |request| self.send(request.opcode, request.sequence, .ok, request.transfer_ticks),
            }
        }
    };
}
test "production service uses interchangeable byte transport and returns every logit" {
    const std = @import("std");
    const model = @import("model.zig");
    const M = model.Sequential(.{model.Dense(.{ .input = 2, .output = 2, .weights = &.{ 1, 0, 0, 1 }, .bias = &.{ 0, 0 } })});
    const Fake = struct {
        pub const clock_hz = 10000;
        var ticks: u32 = 0;
        var at: usize = 0;
        var frame: [16]u8 = undefined;
        var answer: [60]u8 = undefined;
        var count: usize = 0;
        pub fn init() u32 {
            return 0;
        }
        pub fn now() u32 {
            ticks += 1;
            return ticks;
        }
        pub fn highWater() u16 {
            return 0xffff;
        }
        pub fn read() union(enum) { none, byte: u8, failure } {
            if (at == frame.len) return .none;
            defer at += 1;
            return .{ .byte = frame[at] };
        }
        pub fn write(bytes: []const u8) bool {
            @memcpy(answer[0..bytes.len], bytes);
            count = bytes.len;
            return true;
        }
    };
    _ = try protocol.request(&Fake.frame, .infer, 7, 123, &.{ 3, 9 });
    var server: Service(M, Fake) = undefined;
    server.init(123);
    for (0..Fake.frame.len) |_| server.step();
    const response = try protocol.decodeResponse(Fake.answer[0..Fake.count]);
    try std.testing.expectEqual(@as(u8, 1), response.class);
    try std.testing.expectEqualSlices(u8, &.{ 3, 9 }, response.logits);
}
