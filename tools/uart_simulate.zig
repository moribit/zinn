//! Deterministic host-only transport test. Its clock values are NOT MCU timings.
const std = @import("std");
const z = @import("zinn");
const m = @import("trained_model");
const Fake = struct {
    pub const clock_hz = 10000;
    var ticks: u32 = 0;
    var cursor: usize = 0;
    var bytes: []const u8 = &.{};
    var response: [14 + z.protocol.metric_bytes + m.Model.output_len]u8 = undefined;
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
        if (cursor == bytes.len) return .none;
        defer cursor += 1;
        return .{ .byte = bytes[cursor] };
    }
    pub fn write(frame: []const u8) bool {
        @memcpy(response[0..frame.len], frame);
        count = frame.len;
        return true;
    }
};
pub fn main(init: std.process.Init) !void {
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    if (args.len != 3) return error.ExpectedRequestAndResponsePaths;
    Fake.bytes = try std.Io.Dir.cwd().readFileAlloc(init.io, args[1], init.arena.allocator(), .limited(m.Model.input_len + 15));
    var server: z.Service(m.Model, Fake) = undefined;
    server.init(m.model_id);
    for (0..Fake.bytes.len + 3000) |_| {
        server.step();
        if (Fake.count != 0) break;
    }
    if (Fake.count == 0) return error.NoSimulatedResponse;
    try std.Io.Dir.cwd().writeFile(init.io, .{ .sub_path = args[2], .data = Fake.response[0..Fake.count] });
}
