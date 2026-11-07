const std = @import("std");
const m = @import("model.zig");
pub fn main(init: std.process.Init) void {
    var ws: m.Model.Workspace = undefined;
    var input: [2]i8 = undefined;
    var output: [2]i8 = undefined;
    var checksum: u32 = 0;
    const iterations = 100_000;
    const start = std.Io.Clock.awake.now(init.io);
    for (0..iterations) |i| {
        const ptr: *volatile [2]i8 = &input;
        ptr.* = m.inputs[i % 4];
        m.Model.infer(&input, &output, &ws);
        const result: *volatile [2]i8 = &output;
        checksum +%= @intCast(result.*[1]);
    }
    const ns = start.durationTo(std.Io.Clock.awake.now(init.io)).toNanoseconds();
    std.debug.print("XOR host: iterations={d} ns_total={d} ns/inference={d} checksum={d}\n", .{ iterations, ns, @divTrunc(ns, iterations), checksum });
}
