const fun = @import("ch32fun");
const m = @import("trained_model");
comptime {
    m.Model.checkBudget(.{});
}
pub const ch32fun_swio_log_enabled = true;
var workspace: m.Model.Workspace = undefined;
var input: [m.Model.input_len]i8 = undefined;
var output: [m.Model.output_len]i8 = undefined;
pub fn main() noreturn {
    fun.system.init(.{});
    fun.swio_log.init();
    fun.swio_log.waitForTerminal();
    const runtime: *volatile [m.Model.input_len]i8 = &input;
    runtime.* = m.inputs[0];
    const start = fun.time.nowCycles();
    asm volatile ("" ::: .{ .memory = true });
    m.Model.infer(&input, &output, &workspace);
    asm volatile ("" ::: .{ .memory = true });
    const elapsed = fun.time.nowCycles() -% start;
    var ok = true;
    for (output, m.expected[0]) |actual, expected| ok = ok and actual == expected;
    fun.swio_log.info("MNIST sample0 class={d} reference_ok={d} cycles={d}", .{ @import("zinn").argmax(&output).?, @intFromBool(ok), elapsed });
    while (true) asm volatile ("wfi");
}
