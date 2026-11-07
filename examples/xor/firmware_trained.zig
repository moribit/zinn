const fun = @import("ch32fun");
const m = @import("trained_model");
comptime {
    m.Model.checkBudget(.{});
}
pub const ch32fun_swio_log_enabled = true;
var ws: m.Model.Workspace = undefined;
var input: [2]i8 = undefined;
var output: [2]i8 = undefined;
pub fn main() noreturn {
    fun.system.init(.{});
    fun.swio_log.init();
    fun.swio_log.waitForTerminal();
    for (m.inputs, m.expected, 0..) |vector, expected, i| {
        // Volatile access prevents compile-time folding of the inference.
        const runtime_input: *volatile [2]i8 = &input;
        runtime_input.* = vector;
        const start = fun.time.nowCycles();
        asm volatile ("" ::: .{ .memory = true });
        m.Model.infer(&input, &output, &ws);
        asm volatile ("" ::: .{ .memory = true });
        const elapsed = fun.time.nowCycles() -% start;
        const ok = output[0] == expected[0] and output[1] == expected[1];
        fun.swio_log.info("xor {d}: {d},{d} ok={d} cycles={d}", .{ i, output[0], output[1], @intFromBool(ok), elapsed });
    }
    @import("quant_probe.zig").run();
    while (true) asm volatile ("wfi");
}
